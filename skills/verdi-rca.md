---
name: verdi-rca
description: "Hardware simulation Root Cause Analysis methodology — guides AI through error log parsing, hypothesis generation, waveform-based verification, and causal chain construction. Use when debugging simulation failures with FSDB/VDB data."
---

# Hardware Simulation Root Cause Analysis

This skill encodes the debug thinking framework for analyzing hardware simulation failures. It defines *what to look for* and *how to reason* about failures. For API details on accessing waveform and coverage data, see the `verdi-waveform` and `verdi-coverage` skills.

## 1. RCA Framework Overview

Root cause analysis follows six sequential phases:

```
Phase 1: Error Log Parsing
    ↓
Phase 2: Initial Reconnaissance
    ↓
Phase 3: Hypothesis Generation
    ↓
Phase 4: Hypothesis Verification Loop
    ↓
Phase 5: Causal Chain Construction
    ↓
Phase 6: Report
```

- **Phase 1** extracts structured data from raw error logs.
- **Phase 2** validates that FSDB/VDB data covers the failure and samples key signals.
- **Phase 3** maps the error type to ranked hypotheses and identifies first signals to check.
- **Phase 4** iteratively tests each hypothesis against waveform evidence.
- **Phase 5** builds a verified chain from root cause to observed failure.
- **Phase 6** produces a structured report with evidence and fix suggestions.

Each phase must complete before advancing to the next. If any phase produces insufficient data, stop and request guidance from the user.

## 2. Phase 1: Error Log Parsing

### What to extract

From every error log, extract these fields (use `null` if not found):

| Field | Description | Example |
|-------|-------------|---------|
| Failure timestamp | Simulation time of the error | `42350 ns` |
| Error type | Category of failure | `assertion failure`, `timeout`, `data mismatch` |
| Signal/scope names | Hierarchical signal or scope paths mentioned | `top.cpu.alu.result` |
| Expected vs. actual | What was expected and what was observed | `Expected: 0xDEAD, Got: 0xBEEF` |
| Test name | Name of the test or sequence that failed | `test_write_burst_seq` |
| Seed | Random seed for reproducibility | `seed=12345` |

### Common error log formats

**VCS errors:**
```
Error-[ERRORCODE] at time X
```

**UVM errors and fatals:**
```
UVM_ERROR @ time: component [ID] message
UVM_FATAL @ time: component [ID] message
```

**Assertion failures:**
```
Assertion assertion_name failed at time T
```

**Timeouts:**
```
Timeout waiting for event_name at time T
```

**Data mismatches:**
```
Expected: X, Got: Y at address Z
```

### Extraction strategy

1. Scan the log bottom-up — the most actionable error is usually the first fatal or the last error before simulation ended.
2. Ignore `UVM_WARNING` unless no `UVM_ERROR` or `UVM_FATAL` exists.
3. If multiple errors exist, group by timestamp — errors at the same time are often symptoms of a single root cause.
4. Extract the earliest error timestamp as the primary investigation target.

## 3. Phase 2: Initial Reconnaissance

Before forming hypotheses, verify that the available data covers the failure and gather context.

### Step 1: Validate FSDB coverage

Open the FSDB and check whether the failure time falls within the dump window:

```python
f = waveform.open("dump.fsdb")
min_t = f.min_time()
max_t = f.max_time()
# Is failure_time between min_t and max_t?
```

If `failure_time > max_t`, the FSDB was truncated before the failure. Report this to the user — the simulation may have crashed or dump was stopped early.

If `failure_time < min_t`, the FSDB dump started after the failure. The user needs to re-run with an earlier dump start.

### Step 2: Dump scope hierarchy

```python
waveform.hier_tree_dump_scope(f, "/tmp/scopes.txt")
```

Review the scope tree to understand the design hierarchy and locate the scope(s) relevant to the failure.

### Step 3: Sample key signals at failure time

Using signal/scope names extracted from the error log, query their values at and around the failure time:

```python
val_at = waveform.sig_value_at(f, signal_name, failure_time, waveform.VctFormat_e.HexStrVal)
val_before = waveform.sig_value_at(f, signal_name, failure_time - 100, waveform.VctFormat_e.HexStrVal)
```

Check for X/Z values — these are immediate red flags.

### Step 4: Check coverage (if VDB available)

If a VDB file is available, check coverage of the instances involved in the failure. Low coverage on a specific instance may indicate untested corner cases or dead code.

## 4. Phase 3: Hypothesis Generation

Map the error type to a ranked list of hypotheses. Investigate in order — most common root causes first.

| Error Type | Typical Hypotheses | First Signals to Check |
|---|---|---|
| Assertion failure | 1. Precondition violated 2. Design bug in asserted logic 3. Missing/wrong constraint in testbench | Assertion trigger signals, input conditions that feed the assertion |
| Data mismatch | 1. Incorrect computation in data path 2. Wrong mux select line 3. Stale or latched data | Data output, mux select lines, write-enable and clock-enable signals |
| Timeout / hang | 1. FSM stuck in a state 2. Handshake deadlock (both sides waiting) 3. Clock gating preventing progress | State machine register, handshake signal pairs (valid/ready, req/ack), gated clock |
| X-propagation | 1. Uninitialized register after reset 2. Floating wire (undriven net) 3. Power domain or retention issue | Signal showing X, reset signal, initialization sequence signals |
| Protocol violation | 1. Missing handshake signal 2. Wrong ordering of protocol phases 3. Timing violation (setup/hold in protocol sense) | Protocol control signals: valid, ready, req, ack, data, addr |

### Prioritization rules

- If the error log contains explicit expected/actual values, prioritize data path hypotheses.
- If the error mentions a timeout or watchdog, prioritize FSM and handshake hypotheses.
- If X values are visible in any sampled signal, prioritize X-propagation regardless of the stated error type — X is often the hidden root cause of other failures.

## 5. Phase 4: Hypothesis Verification Loop

For each hypothesis (in priority order):

```
1. IDENTIFY signals to check
   - From error context (signal names in the log)
   - From domain knowledge (e.g., FSM state register for a hang)
   - From the hypothesis itself (e.g., mux select for a data mismatch)

2. QUERY waveform values at relevant times
   - At the failure time
   - In a window before the failure (look for the triggering transition)
   - At reset deassertion (for initialization issues)

3. EVALUATE evidence
   - Does the signal value SUPPORT the hypothesis? → trace deeper
   - Does the signal value REFUTE the hypothesis? → move to next hypothesis
   - Is the evidence AMBIGUOUS? → gather more data (wider time range, more signals)

4. TRACE DEEPER (if supported)
   - Follow the driver chain: what drives this signal?
   - Use lang.trace_driver2() or manual hierarchy knowledge
   - Check the driver signal at the same time
   - Repeat until the originating cause is found

5. RECORD findings
   - Signal name, time, value, and interpretation
   - Whether this supports or refutes the hypothesis
```

### Iteration limits

- Check a maximum of 5 hypotheses before escalating to the user.
- For each hypothesis, query a maximum of 20 signals before concluding it is supported, refuted, or ambiguous.

## 6. When to Stop Tracing

Three explicit stop conditions. When any is met, stop and report to the user.

**Stop Condition 1: Driver chain depth exceeded**
If 3 or more levels of driver chain have been traced without finding a clear root cause, escalate. Present the partial chain and ask the user for domain guidance on where to look next.

**Stop Condition 2: Signal outside FSDB dump scope**
If tracing leads to a signal that is not present in the FSDB (the scope or signal does not exist in the dump), report the boundary. Tell the user which signal was being traced and that it falls outside the dump window or scope filter. Ask whether they can provide a broader FSDB or point to the relevant scope.

**Stop Condition 3: Multiple equally plausible hypotheses**
If after verification, 2 or more hypotheses remain equally supported by the evidence, present the top 2-3 candidates with the evidence for each. Let the user decide which direction to pursue, or suggest additional signals to disambiguate.

## 7. Phase 5: Causal Chain Construction

Once a root cause is identified, build the complete causal chain from root cause to observed failure.

### Chain format

Each link in the chain must include:

```
[Link N] signal_name @ time = value
  → WHY this caused the next effect
[Link N+1] next_signal @ time = value
  → ...
[Final] observed_failure_signal @ failure_time = wrong_value
```

### Verification

- Every link must be backed by a waveform query showing the stated signal, time, and value.
- The causal relationship between links must be explainable (e.g., "this signal drives that mux select, which chose the wrong input").
- If any link cannot be verified with waveform data, mark it as INFERRED and note the gap.

### Example chain

```
[Root] top.cpu.ctrl.wr_en @ 4200ns = 0
  → Write enable was deasserted due to FSM being in IDLE state
[Link] top.cpu.ctrl.state @ 4200ns = IDLE
  → FSM never transitioned from IDLE because req was X
[Link] top.cpu.ctrl.req @ 4200ns = x
  → req is X because it was never initialized after reset
[Observed] top.cpu.dout @ 4350ns = 0xXXXX (expected 0xDEAD)
```

## 8. Phase 6: Report

### Report structure

```
## Root Cause
- Signal: <full hierarchical name>
- Time: <simulation time>
- Condition: <what went wrong and why>

## Causal Chain
<Full chain from Phase 5, with waveform evidence at each step>

## Coverage Gaps (if VDB available)
- <Instance or coverpoint with low/zero coverage relevant to the failure>

## Suggested Fix Direction
- <Actionable suggestion: RTL fix, testbench constraint, reset sequence, etc.>

## Elimination Evidence
- <Signals and hypotheses that were checked and ruled out, with reasons>
```

### Status codes

End every report with one of these status codes:

| Status | Meaning |
|--------|---------|
| `DONE` | Root cause identified with full causal chain and waveform evidence |
| `DONE_WITH_CONCERNS` | Root cause identified but some links in the chain are inferred, not verified |
| `NEEDS_CONTEXT` | Stopped due to missing data (FSDB scope, signals not dumped, etc.) — user input needed |
| `BLOCKED` | Unable to make progress — multiple hypotheses equally plausible, or no matching signals found |

## 9. Debug Recipes

### Clock / Reset Issues

1. Check clock activity around failure time:
   ```python
   waveform.sig_value_between(f, "clk", t - 100, t + 100, waveform.VctFormat_e.BinStrVal)
   ```
2. Check reset state:
   ```python
   waveform.sig_value_at(f, "rst_n", t, waveform.VctFormat_e.BinStrVal)
   ```
3. Check for glitches in the FSDB:
   ```python
   f.has_glitch()
   ```
4. Count clock edges to verify clock is toggling:
   ```python
   waveform.sig_vc_count(f, "clk", t - 1000, t)
   ```
5. If clock edge count is 0, the clock is stuck. Trace upstream: clock source, PLL, clock gate enable.

### FSM Stuck

1. Find the state signal — look for signals named `*state*`, `*fsm*`, `*cs*`, `*ns*` in the relevant scope:
   ```python
   # Dump signals in the scope and search for state-like names
   waveform.hier_tree_dump_sig(f, "/tmp/sigs.txt", scope)
   ```
2. Check state transitions over a window before the failure:
   ```python
   waveform.sig_value_between(f, state_sig, t - 1000, t, waveform.VctFormat_e.HexStrVal)
   ```
3. Identify the last valid state transition — what was the state before it got stuck?
4. Check the next-state logic inputs: enable signals, clock gating, condition signals that should trigger the transition.
5. If the state has not changed for an unexpectedly long period, the FSM is stuck. The root cause is in whatever condition prevents the next transition.

### Data Path Debug

1. Start at the output signal showing the wrong value.
2. Trace the driver chain (use `lang.trace_driver2()` if available, or follow the design hierarchy manually).
3. Check each intermediate signal at the failure time:
   ```python
   waveform.sig_value_at(f, intermediate_sig, t, waveform.VctFormat_e.HexStrVal)
   ```
4. Find the first signal in the chain that has the CORRECT value. The next signal downstream has the WRONG value. The bug is in the logic between them.
5. Focus investigation on the logic between the last correct and first incorrect signal.

### X-Propagation

1. Find when X first appeared on the failing signal:
   ```python
   waveform.sig_find_x_backward(f, sig, failure_time, waveform.VctFormat_e.BinStrVal)
   ```
2. Find the earliest X in the signal's entire history:
   ```python
   waveform.sig_find_x_forward(f, sig, 0, waveform.VctFormat_e.BinStrVal)
   ```
3. At the time X first appeared, trace the active driver:
   ```python
   # Use lang.active_trace_driver(sig, x_time) if available
   ```
4. Repeat for each driver signal until the originating X source is found — the signal that was never initialized or is undriven.
5. Check the reset and initialization sequence around the X origin time:
   ```python
   waveform.sig_value_at(f, "rst_n", x_origin_time, waveform.VctFormat_e.BinStrVal)
   ```
6. Common X origins: register without reset value, wire with no driver, power domain that was off.

### Protocol Violation

1. Identify the protocol signal set (valid, ready, req, ack, data, addr).
2. Check both sides of the handshake around the violation time:
   ```python
   waveform.sig_value_between(f, "valid", t - 50, t + 50, waveform.VctFormat_e.BinStrVal)
   waveform.sig_value_between(f, "ready", t - 50, t + 50, waveform.VctFormat_e.BinStrVal)
   ```
3. Look for ordering violations — was valid asserted before data was stable? Was ready dropped while valid was still high?
4. Check for missing responses — find the next assertion of the expected response:
   ```python
   waveform.sig_find_value_forward(f, "ack", "1", t, waveform.VctFormat_e.BinStrVal)
   ```
5. If no response is found before `max_time()`, the responder never replied — investigate why.

## 10. Error Log Pattern Recognition

Use these regex patterns to extract structured data from common simulation log formats.

### UVM errors

```
UVM_ERROR\s+@\s+(\d+)\s*:\s*(.*)
```
- Group 1: simulation time
- Group 2: error message

### UVM fatals

```
UVM_FATAL\s+@\s+(\d+)\s*:\s*(.*)
```
- Group 1: simulation time
- Group 2: fatal message

### Assertion failures

```
Assertion\s+(\S+)\s+failed.*time\s+(\d+)
```
- Group 1: assertion name
- Group 2: failure time

### VCS errors

```
Error-\[(\w+)\].*time\s+(\d+)
```
- Group 1: error code
- Group 2: time

### Timeouts

```
[Tt]imeout.*?(\d+)\s*(ns|ps|us)
```
- Group 1: time value
- Group 2: time unit

### Data mismatches

```
[Ee]xpect.*?:\s*(\w+).*?[Gg]ot.*?:\s*(\w+)
```
- Group 1: expected value
- Group 2: actual value

### Usage

Apply these patterns to the error log in Phase 1 to automatically extract the structured fields. If a pattern does not match, fall back to manual parsing of the log line.

---

## 11. Systematic VMOD/HLS Debug Methodology

This section captures the end-to-end analysis flow proven on real HLS VMOD testbench failures. Follow this sequence for any TRANSACTION_MISMATCH or data comparison error in HLS-based designs.

### Step 1: Identify the Two FSDBs

VMOD test environments often have multiple FSDB files:
- **Regression FSDB** (small, in test output directory) — the actual failing run
- **Debug FSDB** (larger, in p2r_vmod_test or similar) — may be a different run or reference

Always use the FSDB from the **actual failing test directory** for analysis. Verify by checking the time range covers the error timestamp.

```python
f = waveform.open(fsdb_path)
print(f"Time: {f.min_time()} to {f.max_time()}, scale: {f.scale_unit()}")
# Error at 446ns with 10ps scale → t=44600. Check max_time >= 44600.
```

### Step 2: Parse Error Log — Extract ACTUAL vs EXPECTED Fields

For TRANSACTION_MISMATCH errors, extract every field with its **bit-width** and **value**:

```
ACTUAL   {nodeId (9)=3 sliceId (3)=0 padr (46)=8afab4 ...}
EXPECTED {nodeId (9)=f sliceId (3)=2 padr (46)=115f564 ...}
```

Key info to extract:
- Field names and bit-widths (e.g., `nodeId (9)` = 9-bit field)
- Actual vs expected values for each field
- Which fields MATCH and which MISMATCH
- Error time and transaction index

**Critical**: when ALL or MOST fields mismatch, suspect a fundamental input error (wrong data, wrong config, bit-width truncation), not a logic bug in one specific field.

### Step 3: FSDB Reconnaissance — Map the DUT

Dump the signal hierarchy and identify three signal groups:

```python
waveform.hier_tree_dump_sig(f, "/tmp/sigs.txt", expand=1)
```

1. **Input interface signals** — `i_pd_rsc_dat`, `i_pd_rsc_vld`, `i_pd_rsc_rdy` and unpacked fields
2. **Output interface signals** — `o_pd_rsc_dat`, `o_pd_rsc_vld`, `o_pd_rsc_rdy` and unpacked fields
3. **DUT internal signals** — pipeline stages, intermediate computations, config registers

### Step 4: Locate the First Output Transaction

Find when `o_pd_rsc_vld` first goes high and read ALL output fields at that time:

```python
changes = waveform.sig_value_between(f, "...o_pd_rsc_vld", 0, f.max_time(), fmt)
for t, v in changes:
    if v == '1':
        # Read all output fields at time t
        nodeId = waveform.sig_value_at(f, "...nodeId", t, fmt)
        # ... etc
```

Verify: do the waveform values match the scoreboard's ACTUAL values? They should be identical. If not, you're looking at the wrong FSDB or wrong signal.

### Step 5: Trace Input → Output Pipeline Timing

Build a timeline showing when inputs arrive and when outputs emerge:

```python
# Check input valid transitions
in_vld = waveform.sig_value_between(f, "...in_valid", 0, max_t, fmt)
# Check output valid transitions
out_vld = waveform.sig_value_between(f, "...out_valid", 0, max_t, fmt)
```

Determine:
- **Pipeline latency**: how many cycles from `in_valid` to `out_valid`?
- **Which input produced which output**: match by counting transaction order
- **Config timing**: does config change between input acceptance and output production?

### Step 6: Decode Packed Data Buses

For packed interfaces (`rsc_dat` buses), decode field-by-field using the HESS interface definition:

```python
dat_bin = waveform.sig_value_at(f, "...i_pd_rsc_dat", t, waveform.VctFormat_e.BinStrVal)
dat = int(dat_bin, 2)
address     = (dat >>  0) & ((1 << 52) - 1)
aperture    = (dat >> 52) & ((1 <<  2) - 1)
clientkind  = (dat >> 54) & ((1 <<  3) - 1)
# ... decode all fields per interface spec
```

**Compare decoded values against the waveform's unpacked signals.** Any discrepancy reveals a packing/unpacking bug.

### Step 7: Bit-Width Audit — The Most Common HLS Wrapper Bug

**This is the highest-priority check for HLS VMOD failures.** HLS-generated cores have precise bit-widths from the C model (`ac_int<N>`), but hand-written wrappers often have width mismatches.

Audit checklist — for EVERY signal crossing the wrapper boundary:

1. **Read the HLS C model** (`*_impl.h` / `*_hls.h`) to get the golden bit-widths
2. **Read the wrapper RTL** (`*_core.v`, `*_tb.v`) to get the port widths
3. **Check for truncation** at each level:

```
C model width → HLS port width → Wrapper port width → TB extraction width
     N bits    →    N bits      →    M bits (M<N?)   →    K bits (K<M?)
```

Common patterns:
- **Port too narrow**: `input [22:0] secure_top` when C model needs `ac_int<24>` → MSB lost
- **Zero-padding hides the bug**: `assign full_sig = {zeros, narrow_port}` — looks correct but MSB is always 0
- **Truncation in extraction**: `assign narrow = wide[K:0]` drops upper bits silently
- **Width matches but position wrong**: field extracted from wrong bit range in packed bus

**Red flags to grep for:**

```bash
# Find zero-padding (potential truncation hiding)
grep -n "{{.*1'b0.*}}" wrapper.v

# Find bit-range extractions that might truncate
grep -n "\[.*:0\]" wrapper.v

# Compare port widths vs C model widths
grep "input.*\[" wrapper.v | sort
grep "ac_int<" model.h | sort
```

### Step 8: Verify with Waveform — The Smoking Gun

Once you suspect a specific bit-width truncation, verify from the waveform:

```python
# Decode the FULL field from the packed bus
dat = int(waveform.sig_value_at(f, "...rsc_dat", t, bfmt), 2)
full_field = (dat >> start_bit) & ((1 << full_width) - 1)

# Read the truncated port value
truncated = int(waveform.sig_value_at(f, "...port_signal", t, hfmt), 16)

print(f"Full field ({full_width}b): 0x{full_field:x}")
print(f"Port value ({port_width}b): 0x{truncated:x}")
print(f"MSB lost: {full_field != truncated}")
```

If `full_field != truncated`, you've found the bug. The difference tells you exactly which bits are lost.

### Step 9: Confirm Causality — Does the Truncation Explain ALL Mismatches?

A true root cause must explain ALL mismatched output fields, not just one. The memory partitioning logic uses the truncated value to compute nodeId, sliceId, AND padr. If one input is corrupted, all outputs derived from it will be wrong.

Check: do the MATCHING fields (e.g., hshubID=0, mp_local_illegal=0) make sense with the truncated input? Often, fields that happen to be 0 are unaffected by the truncation.

### Step 10: Document the Fix

For bit-width fixes, specify:
1. **Which file and line** has the truncation
2. **Current width** vs **required width**
3. **All signals in the chain** that need widening (port, wire, assignment)
4. **Test data that triggers the bug** (the specific value with the MSB set)

### Summary: HLS VMOD Debug Priority Order

When debugging HLS VMOD test failures:

1. **Bit-width audit FIRST** — most common HLS wrapper bug, highest ROI
2. **Input data alignment** — is the DUT processing the right transaction?
3. **Config synchronization** — are config and data properly paired through the pipeline?
4. **Pipeline timing** — does the output correspond to the expected input?
5. **Logic errors** — actual computation bugs (least common in HLS-generated code)

The HLS core itself is almost always correct (it's generated from verified C). The bugs are in the **hand-written wrappers** that connect the HLS core to the testbench.

---

## 12. Full-Stack Debug Methodology (FSDB + KDB + VDB)

This section describes the complete debug methodology using ALL available data sources — not just waveforms. The key principle: **extract everything from the database, never rely on reading source code manually**.

### Data Sources and What They Provide

| Source | API | What You Get | When to Use |
|--------|-----|-------------|-------------|
| **FSDB** | `pynpi.waveform` | Signal values over time, transitions, X-values | Always — primary debug data |
| **KDB** (simv.daidir) | `pynpi.lang`, `pynpi.netlist` | RTL structure, signal tracing, source file/line, connectivity | When you need to trace drivers/loads or understand design structure |
| **VDB** | `pynpi.cov` | Coverage metrics, uncovered bins, assertion status | When investigating coverage gaps or assertion failures |

### Loading Multiple Sources

```python
from pynpi import npisys, waveform, lang, netlist, cov

npisys.init([sys.argv[0]])

# Load KDB for design structure (MUST load before querying lang/netlist)
npisys.load_design([sys.argv[0], "-dbdir", "/path/to/simv.daidir"])

# Open FSDB for waveform data
f = waveform.open("/path/to/test.fsdb")

# Open VDB for coverage (if available)
db = cov.open("/path/to/simv.vdb")
```

### Step-by-Step Full-Stack Debug Flow

#### Step 1: Error Classification (from sim log)

Parse the error log to classify the failure type:

| Error Pattern | Classification | Primary Investigation |
|--------------|---------------|----------------------|
| `TRANSACTION_MISMATCH` | Data mismatch | Compare expected vs actual field-by-field |
| `No matching fmod entry for vmod` | Fmod/vmod divergence | Compare fmod vs vmod outputs on the error interface |
| `UVM_FATAL ... assert` | Assertion failure | Check assertion preconditions |
| X-value in output | Uninitialized/clock gating issue | Trace X-value origin backward |

#### Step 2: Systematic Signal Comparison (FSDB)

When comparing passed vs failed test, or fmod vs vmod:

```python
# Compare ALL simTop signals to find the EXACT configuration differences
simtop_sigs = [s for s in all_sigs if s.startswith("simTop.") and "." not in s.replace("simTop.", "", 1)]
diffs = []
for sig in simtop_sigs:
    vp = waveform.sig_value_at(f_passed, sig, sample_time, HexStrVal)
    vf = waveform.sig_value_at(f_failed, sig, sample_time, HexStrVal)
    if vp and vf and vp != vf and 'Z' not in vp and 'x' not in vp.lower():
        diffs.append((sig, vp, vf))
```

**Critical**: Compare ALL signals systematically, not just the ones you think are relevant. The root cause is often in an unexpected signal.

#### Step 3: X-Value Origin Tracing (FSDB)

When output data contains X values:

```python
# Find when X first appeared
x_first = waveform.sig_find_x_forward(f, signal_name, 0, HexStrVal)  # earliest X
x_last = waveform.sig_find_x_backward(f, signal_name, error_time, HexStrVal)

# Search for X in ALL DUT internal signals at error time
for sig in dut_internal_sigs:
    v = waveform.sig_value_at(f, sig, error_time, HexStrVal)
    if v and ('x' in v.lower() or 'X' in v):
        x_signals.append(sig)
```

This identifies the X propagation chain. The signal with the EARLIEST X time is closest to the origin.

#### Step 4: Design Structure Tracing (KDB — pynpi.lang)

**This is what separates basic wave debug from full RCA.** Use KDB to trace the logic:

```python
# Trace drivers of a signal — find what RTL logic drives it
drivers = lang.trace_driver2("simTop.u_wrapper.output_signal")
for drv in drivers:
    info = lang.get_hdl_info(drv, True, False)
    # Returns: signal name, source file, line number

# Trace loads — find what consumes a signal
loads = lang.trace_load2("simTop.u_wrapper.config_signal")

# Pattern matching — find all signals matching a pattern
found = lang.find_signal_regex("simTop.u_wrapper.u_dut", [".*clk_gate.*", ".*slcg.*"])

# Get signal type and source location
typespec = lang.get_signal_define_typespec("simTop.u_wrapper.u_dut.some_signal")
```

**Key lang APIs for RCA:**
- `lang.trace_driver2(sig)` → find what drives this signal (with RTL source file:line)
- `lang.trace_load2(sig)` → find what reads this signal
- `lang.active_trace_driver(sig, time)` → find which driver was ACTIVE at a specific time (requires FSDB)
- `lang.find_signal_regex(scope, patterns)` → find signals by pattern (with source locations)
- `lang.get_hdl_info(handle, True, False)` → get full info including source file and line number

#### Step 5: Netlist Connectivity (KDB — pynpi.netlist)

```python
# Get instance port map — see exact widths and connections
inst = netlist.get_inst("simTop.u_wrapper.u_dut")
ports = inst.port_list()
for p in ports:
    print(f"{p.name()} dir={p.direction()} size={p.size()}")

# Trace net connectivity
net = netlist.get_net("simTop.u_wrapper.u_dut.output_signal")
drivers = net.driver_list()  # what drives this net
loads = net.load_list()       # what reads this net

# Fan-in/fan-out to registers
fan_in = net.fan_in_reg_list()   # trace back to source registers
fan_out = net.fan_out_reg_list() # trace forward to destination registers
```

#### Step 6: Coverage Gap Correlation (VDB)

If a VDB is available, check whether uncovered paths correlate with the failure:

```python
db = cov.open("simv.vdb")
tests = db.test_handles()
test = tests[0]

# Check coverage near the failing module
inst = db.handle_by_name("simTop.u_wrapper.u_dut.failing_module")
if inst:
    for metric_name, getter in [("line", inst.line_metric_handle),
                                 ("branch", inst.branch_metric_handle),
                                 ("condition", inst.condition_metric_handle)]:
        m = getter()
        if m:
            cvd = m.covered(test)
            cvb = m.coverable(test)
            # Uncovered branches near failure may indicate untested paths
            children = m.child_handles()
            for ch in children:
                if ch.covered(test) < ch.coverable(test):
                    # This uncovered item may be related to the failure
                    pass
```

### Fmod vs Vmod Debug Recipe

For `No matching fmod entry for vmod req` errors:

1. **Identify the mismatching interface** from the error message (e.g., gnic2gxbar port0 src13 vc1)

2. **Compare fmod vs vmod output signals at error time**:
```python
for field in ["valid", "vc", "dst_unit_id", "pd", "credit"]:
    f_val = waveform.sig_value_at(f, f"simTop.f_{iface}_{field}", err_time, HexStrVal)
    v_val = waveform.sig_value_at(f, f"simTop.v_{iface}_{field}", err_time, HexStrVal)
    # f_ prefix = fmod (C model), v_ prefix = vmod (RTL)
```

3. **Check valid timing** — does vmod valid assert at a different time than fmod?
```python
f_ch = waveform.sig_value_between(f, f"simTop.f_{iface}_valid", err_time - 2e6, err_time + 0.5e6, BinStrVal)
v_ch = waveform.sig_value_between(f, f"simTop.v_{iface}_valid", err_time - 2e6, err_time + 0.5e6, BinStrVal)
```

4. **If vmod pd has X values** — trace X origin through clock-gated registers:
```python
# Search for clock gate flops with X
x_sigs = []
for sig in dut_core_sigs:
    if 'clk_gate' in sig or '_q' in sig:  # register outputs
        v = waveform.sig_value_at(f, sig, err_time, HexStrVal)
        if v and 'x' in v.lower():
            x_sigs.append(sig)
# The clock-gated register with X is the origin
```

5. **Use KDB to find the clock gating control logic**:
```python
# Find what controls the clock gate enable
clk_gate_sigs = lang.find_signal_regex(dut_scope, [".*clk_gate.*clk_en.*"])
for sig in clk_gate_sigs:
    drivers = lang.trace_driver2(sig_full_name)
    # This shows the RTL logic that controls clock gating
```

### Perf Analysis Recipe

For performance instability issues (per-port throughput variation):

1. **Normalize all metrics by perf window length**:
```python
# Find perf measurement window from wave
perf_changes = waveform.sig_value_between(f, "simTop.any_perf_valid", 0, max_time, BinStrVal)
perf_start = next(t for t, v in perf_changes if v == '1')
perf_end = next(t for t, v in perf_changes[perf_changes.index((perf_start,'1')):] if v == '0')
window = perf_end - perf_start

# Normalized rate = transaction_count / window_length
rate = count_valid(f, sig, perf_start, perf_end) / (window / 1e6)  # per μs
```

2. **Compute CV at each pipeline stage** to find where variability is amplified:
```python
import statistics
stage_rates = [rate_per_unit for each unit at this stage]
cv = statistics.stdev(stage_rates) / statistics.mean(stage_rates) * 100
# If CV increases between stages, that stage is amplifying variability
```

3. **Systematic comparison between two seeds**:
   - Compare ALL simTop signals (not just the ones you expect to differ)
   - Categorize: which are truly seed-dependent vs which are build-dependent?
   - TB randomization params identical? → problem is in address mapping
   - TB randomization params different? → problem is in stimulus generation

### Key Principles

1. **Database first, source code never** — Use `pynpi.lang` to get source file:line instead of reading .v/.sv files directly. The KDB has the elaborated, resolved view.

2. **Systematic over targeted** — Compare ALL signals, not just suspects. The root cause is often in an unexpected place (e.g., SLCG delay causing X in output register).

3. **Normalize before comparing** — Different seeds/tests have different simulation times. Always normalize throughput by window length.

4. **Trace the full chain** — From symptom (X on output) → through pipeline (clock-gated register) → to root cause (SLCG timing mismatch). Use `sig_find_x_forward/backward` + `lang.trace_driver2` together.

5. **Cross-reference sources** — FSDB tells you WHAT happened (values, timing). KDB tells you WHERE in the code (file:line, connectivity). VDB tells you WHAT'S UNTESTED (coverage gaps). Use all three together.
