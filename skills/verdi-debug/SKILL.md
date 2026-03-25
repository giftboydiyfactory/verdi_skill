---
name: verdi-debug
version: 0.1.0
description: "This skill should be used when the user asks to 'debug a simulation failure', 'analyze this FSDB', 'find root cause', 'read this waveform', 'check coverage', or provides FSDB/VDB file paths with error logs. Also triggers on keywords: fsdb, vdb, waveform, debug, trace, signal, coverage, RCA, root cause, nWave, Verdi."
---

# Verdi Debug Orchestrator

This skill orchestrates autonomous root cause analysis of hardware simulation failures using the verdi-* skill family. When a user provides an FSDB file path and error log, the AI autonomously investigates and diagnoses the root cause by dynamically generating pynpi Python scripts, executing them, interpreting results, and iterating until the failure is explained.

## 1. Trigger Conditions

Activate this skill when any of the following apply:

- User provides an FSDB file path together with an error log or error message
- User asks to debug or analyze a simulation failure
- User asks to read waveform data or coverage data
- User mentions FSDB, VDB, Verdi, nWave, waveform, signal trace, or coverage
- User asks "what happened at time X" or "why did signal Y change"
- User asks for root cause analysis (RCA) of a simulation result

## 2. Orchestration Flow

```
User provides: FSDB path + error log (+ optional VDB path)
    |
    v
[1] Environment Setup (verdi-env skill)
    - Detect Verdi version (user-specified or auto-detect)
    - Verify verdi_exec.sh works
    - Test pynpi import
    |
    v
[2] Error Log Analysis (verdi-rca skill)
    - Parse error log for timestamps, signal names, error types
    - Classify error type
    - Plan initial investigation direction
    |
    v
[3] FSDB Reconnaissance (verdi-waveform skill)
    - Open FSDB, check time range
    - Verify scope hierarchy contains referenced signals
    - Sample key signals at/around failure time
    |
    |-- If VDB provided --> Coverage Analysis (verdi-coverage skill)
    |   - Open VDB, check coverage of relevant instances
    |   - Identify coverage gaps near failure point
    |
    v
[4] Hypothesis Loop (AI-driven)
    - Generate hypotheses based on error type (verdi-rca patterns)
    - For each hypothesis:
      * Use verdi-waveform for value queries
      * Use verdi-netlist for signal tracing (if available)
      * Use verdi-language for RTL correlation (if available)
      * Use verdi-transaction for protocol analysis (if available)
    - Verify or refute each hypothesis with waveform evidence
    |
    v
[5] Build causal chain, report findings
```

## 3. Execution Model

The AI dynamically generates Python code for each investigation step. Code is executed via `~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh`.

### Execution patterns

```bash
# Pattern 1: Write to temp file, execute
cat > /tmp/verdi_analysis.py << 'PYEOF'
import sys, os
# ... analysis code ...
PYEOF
~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh /tmp/verdi_analysis.py

# Pattern 2: Pipe directly
echo '...' | ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```

### Script lifecycle

Every generated script must follow this structure:

```python
import sys
from pynpi import npisys, waveform

npisys.init([sys.argv[0]])
f = None
try:
    f = waveform.open("/path/to/dump.fsdb")
    # ... investigation code ...
    # Print structured output for parsing
finally:
    if f is not None:
        waveform.close(f)
    npisys.end()
```

The AI reads the script output, decides the next step, and generates the next script. Each step builds on the findings of the previous step.

### Output format

Scripts should print structured output for easy parsing. Prefer key=value pairs or JSON:

```python
print(f"TIME_RANGE: min={min_t} max={max_t}")
print(f"SIGNAL_VALUE: sig={sig_name} time={t} value={val}")
print(f"VERDICT: hypothesis=data_mismatch status=SUPPORTED evidence=...")
```

## 4. Detailed Phase Walkthrough

### Phase 1: Environment Setup

Follow the `verdi-env` skill to:

1. Detect the Verdi installation (user-specified > `$VERDI_HOME` > auto-detect).
2. Verify that `~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh` exists and is executable.
3. Run a minimal smoke test to confirm pynpi imports correctly:

```bash
echo 'from pynpi import npisys; npisys.init(["test"]); print("OK"); npisys.end()' | \
  ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```

If the smoke test fails, diagnose using the troubleshooting table in `verdi-env` before proceeding.

### Phase 2: Error Log Analysis

Follow the `verdi-rca` skill, Phase 1 (Error Log Parsing):

1. Extract: failure timestamp, error type, signal/scope names, expected vs. actual values, test name, seed.
2. Use the regex patterns from `verdi-rca` Section 10 to parse common formats (UVM, VCS, assertion, timeout, mismatch).
3. Classify the error type: assertion failure, data mismatch, timeout/hang, X-propagation, protocol violation.
4. Identify the primary investigation target: the earliest error timestamp and most specific signal names.

### Phase 3: FSDB Reconnaissance

Follow the `verdi-rca` skill, Phase 2 (Initial Reconnaissance):

1. Open the FSDB and verify the failure time falls within `min_time()` to `max_time()`.
2. Dump the scope hierarchy to locate relevant scopes.
3. Sample key signals at and around the failure time.
4. Check for X/Z values, which are immediate red flags regardless of error type.

Generate and execute a reconnaissance script that performs all of the above in a single run.

### Phase 4: Hypothesis Loop

Follow the `verdi-rca` skill, Phases 3-4:

1. Map the error type to ranked hypotheses using the table in `verdi-rca` Section 4.
2. For each hypothesis (up to 5 max):
   - Identify signals to check.
   - Generate a Python script to query those signals.
   - Execute and interpret results.
   - Verdict: SUPPORTED, REFUTED, or AMBIGUOUS.
3. For supported hypotheses, trace deeper using the appropriate debug recipe from `verdi-rca` Section 9 (Clock/Reset, FSM Stuck, Data Path, X-Propagation, Protocol Violation).
4. Stop when a root cause is found or a stop condition is met (see `verdi-rca` Section 6).

### Phase 5: Report

Follow the `verdi-rca` skill, Phases 5-6:

1. Build the causal chain with waveform evidence at every link.
2. Produce the report with: Root Cause, Causal Chain, Suggested Fix Direction, Elimination Evidence.
3. End with a status code.

## 5. Key Principles

- **AI decides which APIs to call.** There is no fixed analysis script. The AI reasons about the failure and dynamically selects the next investigation step.
- **Every conclusion requires waveform evidence.** Every claim must cite a specific signal name, time, and value obtained from the FSDB.
- **Support iterative dialogue.** The user can redirect the investigation at any point. Accept new hypotheses, alternative signal names, or scope corrections from the user.
- **All pynpi code must include proper resource cleanup.** Use try/finally. Release all VCT/FT handles. Always call `npisys.end()`.
- **Print structured output.** Use JSON or clear key=value format so the AI can reliably parse script results.
- **Minimize FSDB open/close cycles.** Batch multiple queries into a single script when possible to reduce overhead.

## 6. Phase 1 Limitations

All domain skills are available:

| Skill | Capability |
|-------|-----------|
| `verdi-waveform` | FSDB waveform reading — signal values, VCT, X-search, expression eval |
| `verdi-coverage` | VDB coverage analysis — line, toggle, FSM, branch, condition, assertion |
| `verdi-netlist` | Design netlist — driver/load tracing, fan-in/fan-out, hierarchy |
| `verdi-language` | RTL source model — active trace at time, signal-to-source mapping, pattern matching |
| `verdi-transaction` | Transaction waveforms — AXI/AHB/APB protocol analysis, message extraction |

**Note**: `verdi-netlist` and `verdi-language` require design source files loaded via `npisys.load_design(sys.argv)`. If the user only provides an FSDB without RTL, these capabilities will be limited. Ask the user for source file paths if needed.

## 7. Example Interaction Flow

```
User: "Here's my FSDB at /proj/sim/test.fsdb. The sim failed with:
       UVM_ERROR @ 15000: Data mismatch at addr 0x100: expected 0xDEAD, got 0xBEEF"

AI thinks:
1. Error type: data mismatch
2. Failure time: 15000
3. Key info: addr=0x100, expected=0xDEAD, actual=0xBEEF

AI actions:
Step 1 - Environment setup:
  -> Smoke test verdi_exec.sh with pynpi import -> OK

Step 2 - Error log parsing:
  -> Extracted: time=15000, type=data_mismatch, expected=0xDEAD, actual=0xBEEF, addr=0x100

Step 3 - FSDB reconnaissance:
  -> Open /proj/sim/test.fsdb
  -> Time range: 0 to 20000 (covers failure at 15000)
  -> Dump scope hierarchy -> find relevant scopes
  -> Search for signals related to addr, data at 0x100
  -> Sample data output signals at t=15000

Step 4 - Hypothesis loop:
  Hypothesis 1: Incorrect computation in data path
  -> Query data path output at t=15000 -> value=0xBEEF (wrong)
  -> Query mux select signals -> select=0x1 (expected 0x0)
  -> SUPPORTED: wrong mux select caused wrong data source

  Trace deeper:
  -> When did mux select become wrong? sig_find_value_backward -> t=14800
  -> What drove the mux select at t=14800?
  -> Use lang.active_trace_driver("top.cpu.dp.mux_sel", 14800) to find active driver
  -> Found control signal: ctrl.sel @ t=14800 = 0x1
  -> Why? Check FSM state -> state=WRITE (should be READ at this point)
  -> FSM entered WRITE due to stale request signal

Step 5 - Report:
  Root Cause: top.cpu.ctrl.req_type was not cleared after previous transaction,
  causing FSM to enter WRITE state instead of READ at t=14800.

  Causal Chain:
  [Root]     top.cpu.ctrl.req_type @ 14800 = WRITE (stale from previous txn)
    -> FSM transitioned to WRITE state instead of READ
  [Link]     top.cpu.ctrl.state @ 14800 = WRITE
    -> WRITE state selects mux input 1 instead of input 0
  [Link]     top.cpu.dp.mux_sel @ 14850 = 1
    -> Wrong data source selected for read response
  [Observed] top.cpu.dp.dout @ 15000 = 0xBEEF (expected 0xDEAD)

  Suggested Fix: Clear req_type at end of each transaction, or re-sample
  req_type from the request bus on each new transaction start.

  Status: DONE
```

## 8. Status Codes

End every debug session report with one of these status codes:

| Status | Meaning |
|--------|---------|
| `DONE` | Root cause identified with full causal chain and waveform evidence |
| `DONE_WITH_CONCERNS` | Root cause identified but some causal chain links are inferred, not verified with waveform data |
| `NEEDS_CONTEXT` | Stopped due to missing data (FSDB scope too narrow, signals not dumped, need RTL context) -- user input needed to continue |
| `BLOCKED` | Unable to make progress -- multiple hypotheses equally plausible, or no matching signals found in FSDB |
