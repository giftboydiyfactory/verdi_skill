# Scoreboard Mismatch Debug Methodology

A systematic, repeatable process for debugging fmod (functional model) vs vmod (RTL) mismatches in folded crossbar designs. Works for any scoreboard comparison failure — not tied to any specific module or bug.

## Principles

1. **Transaction-first, timing-second** — fmod is transaction-based with no timing concept. Always compare transaction CONTENT before analyzing timing.
2. **Backward trace from output** — start at the scoreboard comparison point (output interface), trace backward stage by stage until the divergence point is found.
3. **Normalize at every stage** — at each pipeline stage, compare the SAME logical transaction between fmod and vmod, not the same timestamp.
4. **Cross-validate with passed test** — for every divergence found, check if the passed test has the same pattern. If yes, the divergence is normal behavior. If no, it's a potential bug.
5. **Code verification is mandatory** — waveform analysis identifies WHAT diverges; KDB source trace identifies WHY in the RTL code.

## Phase 1: Error Characterization

### Step 1.1: Parse the Exact Error

Extract from the error message:
- **Comparison interface** (e.g., gnic2gxbar port0)
- **Transaction identity** (e.g., src=1, vc=1)
- **Mismatched fields** and their fmod vs vmod values
- **Number of miscompares** — if most fields mismatch, suspect a fundamental routing error; if only 1-2 fields differ, suspect a computation error in those specific fields

### Step 1.2: Categorize the Mismatch

| Pattern | Likely Cause | Investigation Focus |
|---------|-------------|-------------------|
| ALL fields mismatch | Wrong transaction delivered to this port | Port routing/arbitration |
| Only dst_unit_id differs | Routing table or mapping function | dst computation logic |
| Only pd data differs | Data path corruption or bit-width truncation | Data pipeline registers |
| Transaction missing on one port | Arbiter dropped it or routed elsewhere | Credit/grant logic |
| Extra transaction on one port | Duplicate or mis-routed from another port | Arbitration winner selection |

## Phase 2: Output Interface Comparison

### Step 2.1: Enumerate All Transactions

For EVERY port on the output interface, list ALL fmod and vmod transactions:

```python
for port in range(num_ports):
    for prefix, label in [("f_", "fmod"), ("v_", "vmod")]:
        vld_sig = f"simTop.{prefix}{interface}_port{port}_valid"
        ch = waveform.sig_value_between(f, vld_sig, 0, f.max_time(), BinStrVal)
        for t, v in ch:
            if v == '1':
                # Read ALL fields at this time
                dst = waveform.sig_value_at(f, f"simTop.{prefix}{interface}_port{port}_dst_unit_id", t, HexStrVal)
                vc = waveform.sig_value_at(f, f"simTop.{prefix}{interface}_port{port}_vc", t, HexStrVal)
                # ... all other fields
```

### Step 2.2: Build Transaction Map

Create a table showing which transaction goes to which port:

```
fmod: port0 → [txn_A(dst=X), txn_B(dst=Y), ...]
      port1 → [txn_C(dst=Z), ...]
vmod: port0 → [txn_?(dst=?), ...]
      port1 → [txn_?(dst=?), ...]
```

Check:
- Does vmod port0 have a transaction that fmod put on port1? → **Routing error**
- Does vmod have fewer total transactions? → **Transaction dropped**
- Do transactions match content but different port assignment? → **Port mapping error**

## Phase 3: Backward Trace Through Pipeline

The pipeline typically has these stages (names vary by design):

```
Input (TPC/source) → Translation/Computation (sm2sm/XLAT)
  → Fold Pipeline (phase multiplexing)
    → Ingress Arbiter (XIG)
      → Scheduler (XSD) — assigns thread_id/port
        → Crossbar Fabric (XFN) — routes to output port
          → Output Register (clock-gated flop)
            → Output Interface (scoreboard comparison point)
```

### Step 3.1: Start at Output, Find the Routing Decision

The output port is determined by a routing signal (e.g., `dst_mask`, `thd_id`, `dst_id`). Find it:

```python
# Use KDB to trace what drives the output port selection
lang.trace_driver_dump2("path.to.output_port_valid", "/tmp/output_driver.txt")
```

Read the driver chain to find the routing decision point. Typically this is an arbiter grant signal with a `thd_id` or `dst_mask` that encodes the target port.

### Step 3.2: Check the Routing Decision

At the time the routing decision is made:

```python
# What routing signal value was used?
routing_val = waveform.sig_value_at(f, "path.to.routing_signal", grant_time, HexStrVal)

# What SHOULD it be (from fmod perspective)?
# Compare with passed test at the equivalent transaction
routing_val_pass = waveform.sig_value_at(f_pass, "path.to.routing_signal", pass_grant_time, HexStrVal)
```

If routing values differ → trace what drives the routing signal.

### Step 3.3: Trace One Stage Upstream

At each pipeline stage, ask:
1. **What is the INPUT to this stage?** (signal values at the stage's input)
2. **What is the OUTPUT?** (signal values at the stage's output)
3. **Is the transformation correct?** (does output = expected_function(input)?)
4. **Does the passed test have the same input→output relationship?**

```python
# Compare stage input between failed and passed
for fi, label in [(f_fail, "FAIL"), (f_pass, "PASS")]:
    input_val = waveform.sig_value_at(fi, "stage_input_signal", relevant_time, HexStrVal)
    output_val = waveform.sig_value_at(fi, "stage_output_signal", relevant_time, HexStrVal)
    print(f"{label}: input={input_val} → output={output_val}")
```

If input is the same but output differs → **bug is IN this stage**.
If input already differs → move one stage further upstream.

### Step 3.4: Handle Folded Design Pipeline

In folded designs, one physical channel carries multiple logical transactions time-multiplexed:
- `valid_d1` may be multi-bit (e.g., 2 bits for 2 phases)
- `_d1` suffix signals are delayed by one fold cycle
- X values in inactive phases are **normal**
- The split1/split0 outputs represent the unfolded (logical) transactions

**Critical**: distinguish between fold-level signals (time-multiplexed, may have X in inactive phase) and split-level signals (unfolded, should be clean). The fold-level dst_unit_id may change every cycle as different logical transactions pass through. The split-level dst_unit_id is the stable per-transaction value.

### Step 3.5: Check Signal Alignment Across Stages

A common bug pattern: stage N uses a delayed (`_d1`) version of a signal from stage N-1. In a folded pipeline, the `_d1` delay shifts which fold phase is visible:

```python
# Compare: what does the next stage SEE vs what the current stage PRODUCES?
current_stage_output = waveform.sig_value_at(f, "stage_N.output", t, HexStrVal)
next_stage_input = waveform.sig_value_at(f, "stage_N1.input", t, HexStrVal)
next_stage_input_d1 = waveform.sig_value_at(f, "stage_N1.input_d1", t, HexStrVal)

# If next stage uses _d1, it sees the PREVIOUS cycle's value
# This may correspond to a DIFFERENT logical transaction in a folded design
```

## Phase 4: Identify the Divergence Point

The divergence point is where:
- Failed test and passed test have the SAME input to a stage
- But DIFFERENT output from that stage

OR where:
- Fmod and vmod have the SAME input
- But the vmod produces a different output

### Step 4.1: Binary Search Through Pipeline

If the pipeline is long, use binary search:
1. Check middle stage — same or different between fail/pass?
2. If same → bug is downstream. Check 3/4 point.
3. If different → bug is upstream. Check 1/4 point.
4. Repeat until the exact stage is found.

### Step 4.2: Verify with KDB

Once the divergent stage is identified, use KDB to find the RTL code:

```python
# Find the module instance
inst = netlist.get_inst("path.to.divergent_module")
print(f"Module: {inst.def_name()}")
print(f"Source: {inst.file()}:{inst.begin_line_no()}")

# Trace the divergent signal's driver
lang.trace_driver_dump2("path.to.divergent_signal", "/tmp/driver.txt")

# Find related signals in the module
found = lang.find_signal_regex("path.to.module", [".*relevant_pattern.*"])
```

## Phase 5: Root Cause in RTL Code

### Step 5.1: Read the Computation Logic

Using the source file and line number from KDB, read the RTL code that computes the divergent signal. Common patterns:

**Hardcoded value**: A signal that should be computed from inputs is assigned a constant.
```verilog
assign dst_port_id = 2'd0;  // Should be computed, not hardcoded
```

**Missing case**: A case statement doesn't cover all valid opcodes.
```verilog
case(opcode)
    6'd35: result = compute_a();
    6'd36: result = compute_b();
    // Missing: 6'd40, 6'd42, etc.
    default: result = 'x;  // Simulation X, synthesis 0
endcase
```

**Missing reset**: A feedback register has no reset, causing X on first use.
```verilog
always_ff @(posedge clk) begin
    // No reset branch!
    if (valid) reg <= new_value;
end
```

**Wrong delay version**: Pipeline uses `_d1` (delayed) when it should use current, or vice versa.
```verilog
// Using delayed version misaligns with fold phase
assign next_stage_input = current_stage_output_d1;  // Should be non-delayed?
```

**Bit-width truncation**: Port or wire narrower than the computation requires.
```verilog
input [4:0] config_value;  // 5 bits, but C model uses 8 bits
```

### Step 5.2: Cross-Validate with Code Diff

If both passed and failed tests exist:

```bash
# Compare the RTL between two builds
diff old_build/module.v new_build/module.v
```

The diff shows exactly what code changed. The bug is in the changed code.

### Step 5.3: Verify the Fix Direction

Before proposing a fix, verify:
1. **Does the proposed fix match fmod behavior?** — The fmod (C model) is the golden reference.
2. **Does the fix break other cases?** — Check if the buggy code path is exercised by other tests.
3. **Is the fix in generated code?** — If the RTL is generated (e.g., by switchgen, HLS), the fix must be in the generator, not the generated file.

## Phase 6: Evidence Collection

For a complete RCA report, collect:

1. **Error details**: exact error message, time, interface, fields
2. **Transaction comparison table**: fmod vs vmod per-port transactions
3. **Pipeline trace**: per-stage signal values at the failing transaction time
4. **Divergence point**: which stage first produces different output
5. **Code location**: file, line, module name from KDB
6. **Code snippet**: the buggy RTL code
7. **Waveform evidence**: specific signal values that confirm the bug
8. **Passed test comparison**: same signals in the passed test showing correct behavior

## Common Pitfalls

1. **Don't assume X is the bug** — In folded designs, X in inactive phases is normal. Only X in ACTIVE phases or in feedback paths is a real problem.

2. **Don't confuse fold-level with split-level** — Fold-level signals change every clock cycle (time-multiplexed). Split-level signals are per-logical-transaction. Comparing fold-level values at different times compares different transactions.

3. **Don't stop at timing differences** — Fmod is transaction-based. Timing differences between fmod and vmod are expected. Only transaction CONTENT differences matter.

4. **Don't trace everything** — Use the backward-trace methodology. Start at the output, find the first divergence, then go deeper. Don't trace the entire pipeline upfront.

5. **Always check the PASSED test** — A signal being X or "wrong-looking" in the failed test doesn't mean it's the bug. Check if the passed test has the same pattern. If yes, it's normal.

6. **Check generated code** — Many crossbar/arbiter modules are generated by scripts (switchgen, etc.). The bug may be in the generator parameters or template, not in hand-written RTL.
