---
name: verdi-rca
version: 0.1.0
description: "This skill should be used when the user asks to 'debug this failure', 'find root cause', 'compare passed vs failed', 'trace X values', 'analyze fmod vs vmod mismatch', or needs hardware simulation Root Cause Analysis methodology."
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


---

## Additional Resources

### Reference Files

For detailed debug methodologies proven on real hardware failures, consult:

- **`references/hls-vmod-debug.md`** — Systematic VMOD/HLS debug methodology (10-step flow for HLS wrapper bit-width issues, data bus decoding, pipeline analysis)
- **`references/full-stack-debug.md`** — Full-stack debug using FSDB + KDB + VDB together (multi-source loading, KDB trace APIs, fmod vs vmod recipe, perf analysis recipe, coverage gap correlation)
