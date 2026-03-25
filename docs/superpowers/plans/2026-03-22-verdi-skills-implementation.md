# Verdi Skills Plugin — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a Claude Code plugin that lets AI autonomously debug hardware simulation failures by dynamically generating and executing `pynpi` Python code against FSDB waveforms and VDB coverage databases.

**Architecture:** A layered skill plugin — one orchestrator skill (`verdi-debug`) routes to domain skills (`verdi-env`, `verdi-waveform`, `verdi-coverage`, `verdi-netlist`, `verdi-language`, `verdi-transaction`) and a methodology skill (`verdi-rca`). AI reads these skills to learn the APIs, then writes ad-hoc Python code executed via `verdi_exec.sh` using Verdi's bundled Python 3.11. No hardcoded analysis scripts.

**Tech Stack:** Claude Code plugin system (skills, plugin.json), Synopsys Verdi pynpi (Python 3.11, SWIG bindings), Bash

**Spec:** `docs/superpowers/specs/2026-03-22-verdi-skills-design.md`

**Target directory:** `~/.claude/plugins/verdi-skills/`

---

## File Structure

```
~/.claude/plugins/verdi-skills/
├── plugin.json                     # Plugin manifest — evolves per phase
├── scripts/
│   └── verdi_exec.sh               # Environment bootstrap + Python executor
└── skills/
    ├── verdi-debug.md              # Orchestrator (Phase 1)
    ├── verdi-env.md                # Environment detection (Phase 1)
    ├── verdi-waveform.md           # FSDB waveform API (Phase 1)
    ├── verdi-rca.md                # RCA methodology (Phase 1)
    ├── verdi-coverage.md           # VDB coverage API (Phase 2)
    ├── verdi-netlist.md            # Netlist tracing API (Phase 3)
    ├── verdi-language.md           # RTL source + lang tracing API (Phase 3)
    └── verdi-transaction.md        # Transaction waveform API (Phase 3)
```

---

## Phase 1: Core MVP

### Task 1: Plugin scaffold + verdi_exec.sh

**Files:**
- Create: `~/.claude/plugins/verdi-skills/plugin.json`
- Create: `~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh`

- [ ] **Step 1: Create plugin directory structure**

```bash
mkdir -p ~/.claude/plugins/verdi-skills/scripts
mkdir -p ~/.claude/plugins/verdi-skills/skills
```

- [ ] **Step 2: Write plugin.json (Phase 1 version)**

Create `~/.claude/plugins/verdi-skills/plugin.json`:
```json
{
  "name": "verdi-skills",
  "version": "0.1.0",
  "description": "AI-driven Verdi/FSDB/VDB analysis and hardware debug",
  "skills": [
    "skills/verdi-debug.md",
    "skills/verdi-env.md",
    "skills/verdi-waveform.md",
    "skills/verdi-rca.md"
  ]
}
```

- [ ] **Step 3: Write verdi_exec.sh**

Create `~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh` with the full script from the spec (Section 5). Key features:
- `--verdi-home <path>` and `--timeout <secs>` options
- Auto-detect latest stable Verdi from `/home/tools/debussy/verdi3_20*` (exclude Beta)
- Fall back to `$VERDI_HOME` env var
- License warning if `SNPSLMD_LICENSE_FILE` not set
- stdin mode with temp file cleanup via trap
- Timeout default 120s

```bash
#!/bin/bash
# verdi_exec.sh — Execute Python code with Verdi NPI environment
set -euo pipefail

VERDI_HOME_ARG=""
TIMEOUT=120
SCRIPT=""
SCRIPT_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        --verdi-home)
            VERDI_HOME_ARG="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            SCRIPT="$1"
            shift
            SCRIPT_ARGS=("$@")
            break
            ;;
    esac
done

if [[ -n "$VERDI_HOME_ARG" ]]; then
    VERDI_HOME="$VERDI_HOME_ARG"
elif [[ -n "${VERDI_HOME:-}" ]]; then
    VERDI_HOME="$VERDI_HOME"
else
    VERDI_HOME=$(ls -d /home/tools/debussy/verdi3_20* 2>/dev/null \
        | grep -vi beta \
        | sort -V \
        | tail -1)
    if [[ -z "$VERDI_HOME" ]]; then
        echo "ERROR: No Verdi installation found" >&2
        exit 1
    fi
fi

PYTHON="${VERDI_HOME}/platform/linux64/python-3.11/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
    echo "ERROR: Python 3.11 not found at ${PYTHON}" >&2
    exit 1
fi

if [[ -z "${SNPSLMD_LICENSE_FILE:-}" ]] && [[ -z "${LM_LICENSE_FILE:-}" ]]; then
    echo "WARNING: SNPSLMD_LICENSE_FILE not set — NPI may fail with license errors" >&2
fi

export VERDI_HOME
export LD_LIBRARY_PATH="${VERDI_HOME}/share/NPI/lib/linux64:${VERDI_HOME}/platform/linux64/bin:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="${VERDI_HOME}/share/NPI/python:${PYTHONPATH:-}"

echo "Using Verdi: ${VERDI_HOME}" >&2

if [[ -n "$SCRIPT" ]]; then
    timeout "$TIMEOUT" "$PYTHON" "$SCRIPT" "${SCRIPT_ARGS[@]}"
else
    TMPSCRIPT=$(mktemp /tmp/verdi_exec_XXXXXX.py)
    trap 'rm -f "$TMPSCRIPT"' EXIT
    cat > "$TMPSCRIPT"
    timeout "$TIMEOUT" "$PYTHON" "$TMPSCRIPT"
fi
```

- [ ] **Step 4: Make verdi_exec.sh executable**

```bash
chmod +x ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```

- [ ] **Step 5: Verify verdi_exec.sh works**

Test auto-detection and basic Python execution:
```bash
echo 'import sys; print("Python:", sys.version); print("OK")' | ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```
Expected: prints Python version from Verdi's bundled 3.11 and "OK".

Then test pynpi import:
```bash
echo 'from pynpi import npisys; print("pynpi import OK")' | ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```
Expected: prints "pynpi import OK" (may show license warnings).

---

### Task 2: verdi-env.md — Environment Detection Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-env.md`

- [ ] **Step 1: Write verdi-env.md**

This skill teaches AI how to set up the Verdi Python execution environment. It is NOT an API reference — it's procedural knowledge about environment setup.

The skill must contain:
- YAML frontmatter: `name: verdi-env`, `description: ...`
- Verdi installation locations on NVIDIA systems (`/home/tools/debussy/verdi3_*`)
- Version detection algorithm (user-specified → $VERDI_HOME → auto-detect latest stable)
- The `verdi_exec.sh` script path and usage: `~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh`
- Python boilerplate template that ALL generated pynpi scripts must follow:
  ```python
  import sys, os
  VERDI_HOME = "{detected_verdi_home}"
  sys.path.insert(0, VERDI_HOME + "/share/NPI/python")
  os.environ["VERDI_HOME"] = VERDI_HOME
  os.environ["LD_LIBRARY_PATH"] = (...)
  from pynpi import npisys
  npisys.init([sys.argv[0]])  # argv-style list required
  # ... analysis code ...
  npisys.end()
  ```
- Alternative: using `verdi_exec.sh` (handles env setup automatically):
  ```bash
  echo '<python code>' | ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
  # or
  ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh /tmp/analysis.py
  ```
- Common issues and troubleshooting:
  - `_npisys` import failures → `LD_LIBRARY_PATH` is wrong or Verdi's `lib/linux64` not in it
  - License errors → `SNPSLMD_LICENSE_FILE` not set
  - Python version mismatch → must use Verdi's bundled Python 3.11, not system Python
- Resource cleanup: always call `npisys.end()`, release VCT/FT handles, release coverage handles

- [ ] **Step 2: Verify skill file has valid frontmatter**

Check the file starts with proper YAML frontmatter:
```yaml
---
name: verdi-env
description: "Verdi NPI environment setup — detects Verdi version, configures Python execution environment for pynpi. Use when about to execute any pynpi code against FSDB/VDB files."
---
```

---

### Task 3: verdi-waveform.md — FSDB Waveform API Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-waveform.md`

- [ ] **Step 1: Write verdi-waveform.md**

This is the largest and most critical skill. It must contain the COMPLETE `pynpi.waveform` API reference from the spec Section 4.2, organized for easy AI consumption. Include:

**Frontmatter:**
```yaml
---
name: verdi-waveform
description: "Complete pynpi.waveform API reference for reading FSDB waveform files — signal values, scope traversal, value change iteration, X-value search, expression evaluation, force tags, and memory management."
---
```

**Content sections** (from spec + agent research results):

1. **Quick Start** — minimal example: open FSDB, read a signal value, close
2. **File Operations** — `waveform.open()`, `close()`, `is_fsdb()`, `info()`, FileHandle properties (min_time, max_time, scale_unit, has_glitch, etc.)
3. **Scope Traversal** — `file.top_scope_list()`, `file.scope_by_name()`, ScopeHandle methods (name, full_name, def_name, type, parent, child_scope_list, sig_list)
4. **Signal Properties** — SigHandle methods: name, direction, range, composite_type, etc.
5. **L1 Convenience APIs** — `sig_value_at()`, `sig_value_between()`, `sig_vec_value_at()`, `dump_sig_value_between()`, `hier_tree_dump_scope/sig()`, time conversion
6. **Value Change Traverse (VCT)** — `sig.create_vct()`, VctHandle methods (goto_next/prev/first/time, value, time, release). MUST emphasize `release()`.
7. **Force Tag Traverse (FT)** — `sig.create_ft()`, FtHandle methods
8. **VC Iterators** — TimeBasedHandle and SigBasedHandle: add, iter_start/next/stop, get_value, set_max_session_load
9. **X-Value Search** — `sig_find_x_forward/backward()` — critical for X-propagation debug
10. **Value Search** — `sig_find_value_forward/backward()`, `sig_vc_count()`
11. **Expression Evaluator** — SigValueEval: set_wave, set_expr, evaluate, get_edge/posedge/negedge
12. **Memory Management** — `add_to_sig_list()`, `load_vc_by_range()`, `unload_vc()` — when and why to use
13. **Enums** — VctFormat_e, ScopeType_e, DirType_e, SigAssertionType_e, SigCompositeType_e, ForceTag_e, ForceSource_e (with all values)
14. **Common Patterns** — quick check vs range query vs bulk iteration decision tree
15. **Pitfalls** — must release VCT/FT, npisys.end(), large FSDB memory management

**Source material:** Spec Section 4.2 + waveform-api agent output + npi-docs agent waveform section.

- [ ] **Step 2: Verify completeness**

Grep the skill file for these critical APIs to ensure they're all documented:
- `sig_value_at`
- `sig_value_between`
- `sig_find_x_forward`
- `create_vct`
- `SigValueEval`
- `load_vc_by_range`
- `TimeBasedHandle` or `TimeBasedVcIterator`
- `VctFormat_e`

---

### Task 4: verdi-rca.md — RCA Methodology Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-rca.md`

- [ ] **Step 1: Write verdi-rca.md**

This skill encodes the **hardware debug thinking framework**, NOT API details. It tells AI *what to look for* and *how to reason*, while other skills tell it *how to access data*.

**Frontmatter:**
```yaml
---
name: verdi-rca
description: "Hardware simulation Root Cause Analysis methodology — guides AI through error log parsing, hypothesis generation, waveform-based verification, and causal chain construction. Use when debugging simulation failures with FSDB/VDB data."
---
```

**Content sections** (from spec Section 4.7):

1. **RCA Framework Overview** — the 6-phase flow: Error Log Parsing → Initial Recon → Hypothesis Generation → Verification Loop → Causal Chain → Report
2. **Phase 1: Error Log Parsing** — what to extract (timestamp, error type, signal names, expected vs actual, test/seed). Common error log formats from VCS, UVM, assertions.
3. **Phase 2: Initial Reconnaissance** — open FSDB, check time range, sample key signals, check coverage if VDB available
4. **Phase 3: Hypothesis Generation** — the error-type-to-hypothesis table (assertion failure, data mismatch, timeout/hang, X-propagation, protocol violation)
5. **Phase 4: Hypothesis Verification Loop** — pseudocode for the investigate-verify-narrow cycle
6. **When to Stop Tracing** (standalone section, not buried in Phase 4):
   - 3+ levels of driver chain without clear cause → escalate to user
   - Signal trace leads outside FSDB dump scope → report boundary, ask user
   - Multiple equally plausible hypotheses remain → present top 2-3 with evidence to user
7. **Phase 5: Causal Chain** — how to build and verify the chain with waveform evidence
7. **Phase 6: Report** — what to include (root cause signal+time, chain, evidence, coverage gaps, fix direction)
8. **Debug Recipes:**
   - Clock/Reset Issues (with actual API calls using format args)
   - FSM Stuck (signal naming patterns, state transition checks)
   - Data Path Debug (trace driver chain, check intermediates)
   - X-Propagation (using `sig_find_x_forward/backward` + `active_trace_driver`)
   - Protocol Violation (handshake signal timing, transaction analysis)
9. **Error Log Pattern Recognition** — common patterns from VCS/UVM logs:
   - `UVM_ERROR` / `UVM_FATAL` with timestamp extraction
   - Assertion failure messages with signal paths
   - Timeout messages with expected conditions
   - Data comparison mismatches with address/data values

---

### Task 5: verdi-debug.md — Orchestrator Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-debug.md`

- [ ] **Step 1: Write verdi-debug.md**

This is the main entry point — the skill that triggers when a user provides FSDB + error log.

**Frontmatter:**
```yaml
---
name: verdi-debug
description: "Autonomous hardware simulation debug orchestrator. Use when user provides FSDB/VDB waveform files, simulation error logs, or asks to debug/analyze hardware simulation results. Triggers on: fsdb, vdb, waveform, debug, trace, signal, coverage, simulation error, RCA, root cause, nWave, Verdi."
---
```

**Content:**

1. **What this skill does** — orchestrates autonomous RCA using other verdi-* skills
2. **Trigger conditions** — when user mentions FSDB/VDB files, simulation errors, debug requests
3. **Orchestration flow** (from spec Section 4.8):
   - Step 1: Invoke `verdi-env` skill for environment setup
   - Step 2: Invoke `verdi-rca` skill, parse error log, classify error
   - Step 3: Invoke `verdi-waveform` skill, open FSDB, initial recon
   - Step 4 (if VDB provided): Invoke `verdi-coverage` skill for gap analysis
   - Step 5: Hypothesis verification loop (AI-driven, using appropriate domain skills)
   - Step 6: Build causal chain, report findings
4. **Key principles:**
   - AI decides which APIs to call — no fixed script
   - Each step = dynamically generated Python code via `verdi_exec.sh`
   - Must show waveform evidence for all conclusions
   - Support iterative dialogue (user can redirect)
   - Must cleanup resources (npisys.end, release handles)
5. **Phase 1 limitations** — explicitly list what's NOT available yet (no netlist tracing, no RTL correlation, no transaction analysis, no coverage). Tell AI to skip those steps gracefully and note what it cannot do.
6. **Example interaction** — show a brief example flow:
   - User: "Debug this FSDB, here's the error log: ..."
   - AI: sets up env, parses log, opens FSDB, checks signals, forms hypothesis, verifies, reports

---

### Task 6: End-to-end verification

- [ ] **Step 1: Verify plugin loads**

Check that Claude Code can see the plugin:
```bash
ls -la ~/.claude/plugins/verdi-skills/plugin.json
ls -la ~/.claude/plugins/verdi-skills/skills/*.md
ls -la ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```

- [ ] **Step 2: Verify verdi_exec.sh with a real pynpi operation**

Test opening an FSDB-like operation (scope listing):
```bash
cat <<'EOF' | ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
import sys
sys.path.insert(0, __import__('os').environ['VERDI_HOME'] + '/share/NPI/python')
from pynpi import npisys, waveform
npisys.init([sys.argv[0]])
print("NPI initialized successfully")
print("waveform module loaded:", dir(waveform)[:5], "...")
npisys.end()
print("NPI cleanup complete")
EOF
```

Expected: "NPI initialized successfully", module contents, "NPI cleanup complete"

- [ ] **Step 3: Verify skill frontmatter is correct**

For each skill file, ensure the frontmatter parses correctly:
```bash
for f in ~/.claude/plugins/verdi-skills/skills/*.md; do
    echo "=== $(basename $f) ==="
    head -5 "$f"
    echo ""
done
```

---

## Phase 2: Coverage

### Task 7: verdi-coverage.md — VDB Coverage API Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-coverage.md`

- [ ] **Step 1: Write verdi-coverage.md**

**Frontmatter:**
```yaml
---
name: verdi-coverage
description: "Complete pynpi.cov API reference for reading VDB coverage databases — line, toggle, FSM, branch, condition, assertion coverage metrics, test management, exclusions, and gap analysis."
---
```

**Content** (from spec Section 4.3 + coverage-api agent output):

1. **Quick Start** — open VDB, get tests, traverse instances, read coverage
2. **Database Operations** — `cov.open(name, config_opt)`, ConfigOpt enum, `db.close()`
3. **Test Management** — `test_handles()`, `test_by_name()`, `merge_test()`, exclusion loading/saving
4. **Instance Hierarchy** — `instance_handles()`, metric handles (line, toggle, FSM, condition, branch, assert)
5. **Coverage Metric Interface** — common methods: `covered()`, `coverable()`, `count()`, `count_goal()`, `status()`, `has_status_covered/excluded/unreachable()`, `child_handles()`
6. **Coverage Item Classes** — Block, StmtBin, Signal, SignalBit, ToggleBin, Fsm, States, Transitions, Condition, Branch, Assert, Covergroup, Coverpoint, CoverCross, CoverBin
7. **Assertion Report** — `cov.report_assert_coverage()`
8. **Resource Management** — `cov.release_handle()` — MUST release all handles
9. **ConfigOpt** — ExclusionInStrictMode, ExcludeByStmtLevel, LimitedDesign, NoLoadMetricData
10. **Common Patterns** — coverage summary calculation, gap finding, multi-test merge, exclusion workflow

- [ ] **Step 2: Update plugin.json**

Add `"skills/verdi-coverage.md"` to the `skills` array in `~/.claude/plugins/verdi-skills/plugin.json`.

- [ ] **Step 3: Update verdi-debug.md**

Remove the Phase 1 limitation note about coverage. Add coverage analysis to the orchestration flow.

---

## Phase 3: Full Capability

### Task 8: verdi-netlist.md — Netlist Tracing API Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-netlist.md`

- [ ] **Step 1: Write verdi-netlist.md**

**Frontmatter:**
```yaml
---
name: verdi-netlist
description: "Complete pynpi.netlist API reference for design netlist traversal — instance hierarchy, port/net connectivity, driver/load tracing, fan-in/fan-out register chains, and signal-to-signal connection analysis."
---
```

**Content** (from spec Section 4.4 + netlist-lang-api agent output):

1. **Quick Start** — get instance, list nets, trace drivers
2. **Handle Retrieval** — `get_inst()`, `get_port()`, `get_instport()`, `get_net()`, `get_top_inst_list()`
3. **InstHdl** — full method reference: inst_list, net_list, port_list, driver/load instport lists, properties
4. **PinHdl** — connected_pin, connected_net, driver_list, load_list, properties
5. **NetHdl** — driver_list, load_list, fan_in_reg_list, fan_out_reg_list, to_sig_conn_list
6. **Hierarchy Traversal** — hier_tree_trv with callbacks
7. **Connection Tracing** — sig_to_sig_conn_list
8. **Enums** — ObjectType, FuncType, ValueFormat
9. **Common Patterns** — driver trace chain, load fan-out, register-to-register paths

---

### Task 9: verdi-language.md — RTL Source + Language Tracing Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-language.md`

- [ ] **Step 1: Write verdi-language.md**

**Frontmatter:**
```yaml
---
name: verdi-language
description: "Complete pynpi.lang API reference for RTL source analysis — signal driver/load tracing through RTL, active trace at specific simulation time, hierarchy exploration, pattern matching for instances/signals, expression decompilation, and source-to-waveform correlation."
---
```

**Content** (from spec Section 4.5 + netlist-lang-api agent output):

1. **Quick Start** — trace a signal's drivers, find instances by pattern
2. **Signal Tracing** — `trace_driver2()`, `trace_load2()`, dump variants, TrcOption configuration
3. **Active Tracing** — `active_trace_driver()` — time-aware driver trace (KEY for RCA)
4. **Hierarchy & Search** — `get_top_inst_list()`, `handle_by_name()`, `hier_tree_trv()`, dump functions
5. **Pattern Matching** — `find_inst_wildcard/regex()`, `find_signal_wildcard/regex()`
6. **Source Info** — `get_signal_define_typespec()`, `get_hdl_info()`, `verbose_dump()`, `expr_decompile()`
7. **TrcOption Class** — all getter/setter methods for trace configuration
8. **Also available:** `pynpi.text` API for source file reading (file → line → word → macro)
9. **Also available:** `pynpi.sdb` API for static database (libraries, masters, instance tree)

---

### Task 10: verdi-transaction.md — Transaction Waveform Skill

**Files:**
- Create: `~/.claude/plugins/verdi-skills/skills/verdi-transaction.md`

- [ ] **Step 1: Write verdi-transaction.md**

**Frontmatter:**
```yaml
---
name: verdi-transaction
description: "Transaction waveform API reference for analyzing bus protocols (AXI/AHB/APB), messages, and transaction-level activity in FSDB files — stream traversal, transaction attributes, master/slave relations, protocol extraction."
---
```

**Content** (from spec Section 4.6 + waveform-api/npi-docs agent outputs):

1. **Quick Start** — open FSDB, find stream, iterate transactions
2. **FileHandle transaction methods** — top_tr_scope_list, stream_by_name, load_trans/unload_trans, relation_list
3. **TrScopeHandle** — name, full_name, child_tr_scope_list, stream_list, attributes
4. **StreamHandle** — name, full_name, create_trt, attributes
5. **TrtHandle** — id, name, time, type, goto navigation, attributes, related_trt_list, call_stack, release
6. **RelationHandle** — name
7. **Protocol Extraction** — ProtocolExtractor (APB/AHB/AXI)
8. **Message Extraction** — MessageExtractor2
9. **Enums** — RelationDirType_e (Master/Slave), CallStackType_e (Begin/End), TrtType_e (Message/Transaction/Action/Group), Protocol_e (APB/AHB/AXI), ValFormat_e (same as VctFormat_e)

---

### Task 11: Update orchestrator + plugin.json for full capability

- [ ] **Step 1: Update plugin.json**

Add all three Phase 3 skills to the `skills` array in `~/.claude/plugins/verdi-skills/plugin.json`:
```json
"skills/verdi-netlist.md",
"skills/verdi-language.md",
"skills/verdi-transaction.md"
```

- [ ] **Step 2: Update verdi-debug.md**

Remove ALL Phase 1 limitation notes. Update orchestration flow to include all domain skills (netlist tracing, RTL correlation, transaction analysis). The orchestrator should now describe the full debug capability.

- [ ] **Step 3: Final integration test**

Verify all 8 skill files exist, have valid frontmatter, and plugin.json references all of them:
```bash
for f in ~/.claude/plugins/verdi-skills/skills/*.md; do
    name=$(grep "^name:" "$f" | head -1)
    desc=$(grep "^description:" "$f" | head -1)
    echo "$(basename $f): $name | ${desc:0:60}..."
done
```

---

## Phase 4: Refinement (ongoing, no fixed tasks)

- Test with real FSDB/VDB files from actual failing simulations
- Iterate on RCA methodology based on actual debug sessions
- Add more debug recipes to `verdi-rca.md` as patterns emerge
- Optimize skill descriptions for better triggering accuracy
- Consider adding `pynpi.text` and `pynpi.sdb` content to `verdi-language.md`
- Consider Protocol Extraction examples for common bus protocols
