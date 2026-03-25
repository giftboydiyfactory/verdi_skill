# Verdi Skills — Design Specification

**Date**: 2026-03-22
**Status**: Draft (Reviewed)
**Author**: jackeyw + Claude
**API baseline**: `verdi3_2025.06-SP2-2` — earlier versions may have different pynpi APIs

## 1. Goal

Build a Claude Code plugin that enables AI to autonomously debug hardware simulation failures by reading FSDB waveforms, VDB coverage databases, and design netlists via Synopsys Verdi's Python NPI (`pynpi`) API.

**Primary use case**: User provides an FSDB file + simulation error log → AI autonomously performs root cause analysis (RCA) by dynamically generating and executing `pynpi` Python code.

**Design philosophy**: Maximum flexibility — no hardcoded scripts. The skill teaches AI *how* to use `pynpi` APIs and *how* to think about hardware debug, then AI decides which APIs to call and in what order.

## 2. Architecture

### 2.1 Plugin Structure

```
~/.claude/plugins/verdi-skills/
├── plugin.json
├── skills/
│   ├── verdi-debug.md          # Orchestrator: auto-RCA entry point
│   ├── verdi-env.md            # Environment detection & Python execution
│   ├── verdi-waveform.md       # FSDB waveform API reference + patterns
│   ├── verdi-coverage.md       # VDB coverage API reference + patterns
│   ├── verdi-netlist.md        # Netlist traversal + signal tracing
│   ├── verdi-language.md       # RTL source model
│   ├── verdi-transaction.md    # Transaction waveform analysis
│   └── verdi-rca.md            # RCA methodology
└── scripts/
    └── verdi_exec.sh           # Thin wrapper: execute Python with Verdi env
```

### 2.2 Skill Roles

| Skill | Type | Role |
|-------|------|------|
| `verdi-debug` | Orchestrator | User-facing entry point. Triggered when user provides FSDB/VDB + debug request. Invokes other skills as needed. |
| `verdi-env` | Infrastructure | Detects Verdi version, sets up Python execution environment. |
| `verdi-waveform` | API Knowledge | Complete `pynpi.waveform` API reference with usage patterns. |
| `verdi-coverage` | API Knowledge | Complete `pynpi.cov` API reference with usage patterns. |
| `verdi-netlist` | API Knowledge | `pynpi.netlist` API + signal tracing patterns. |
| `verdi-language` | API Knowledge | `pynpi.lang` API + RTL source correlation. |
| `verdi-transaction` | API Knowledge | Transaction waveform API + protocol analysis patterns. |
| `verdi-rca` | Methodology | Hardware debug thinking framework: error log → hypothesis → verification → root cause. |

### 2.3 Execution Model

AI generates Python code dynamically. All code follows this pattern:

```python
import sys, os
VERDI_HOME = "{detected_verdi_home}"
sys.path.insert(0, VERDI_HOME + "/share/NPI/python")
os.environ["VERDI_HOME"] = VERDI_HOME
os.environ["LD_LIBRARY_PATH"] = (
    VERDI_HOME + "/share/NPI/lib/linux64:" +
    VERDI_HOME + "/platform/linux64/bin:" +
    os.environ.get("LD_LIBRARY_PATH", "")
)
from pynpi import npisys
# NPI expects argv-style list; first element = program name (required, even if dummy)
npisys.init([sys.argv[0]])

# === Dynamically generated analysis code ===
# ...

npisys.end()  # MUST call to release all NPI resources
```

Executed via Verdi's bundled Python 3.11 with timeout to prevent runaway scripts:
```
timeout 120 {VERDI_HOME}/platform/linux64/python-3.11/bin/python3 /tmp/verdi_analysis_XXXX.py
```

Temp files should be cleaned up after execution. The `verdi_exec.sh` wrapper handles this via trap.

### 2.4 `verdi_exec.sh` — Environment Bootstrap

The only "hardcoded" component. A thin shell wrapper that:
1. Accepts `--verdi-home <path>` or auto-detects
2. Sets `VERDI_HOME`, `LD_LIBRARY_PATH`, `PYTHONPATH`
3. Executes Python code from stdin or file argument using Verdi's Python 3.11

```bash
#!/bin/bash
# Usage: verdi_exec.sh [--verdi-home /path/to/verdi] script.py [args...]
#    or: echo "python code" | verdi_exec.sh [--verdi-home /path/to/verdi]
```

## 3. Verdi Version Detection

Priority order:
1. User explicitly specifies version (e.g., "use verdi3_2025.06-SP2-2")
2. `$VERDI_HOME` environment variable
3. Scan `/home/tools/debussy/verdi3_*`, select latest stable (exclude Beta)
4. Validate FSDB compatibility with selected version

Detection logic in `verdi-env` skill teaches AI how to:
- Scan `/home/tools/debussy/` for available versions
- Parse version strings for comparison
- Verify `pynpi` Python bindings exist in the selected version
- Check that `{VERDI_HOME}/platform/linux64/python-3.11/bin/python3` exists
- Fall back gracefully if preferred version unavailable

## 4. Skill Details

### 4.1 `verdi-env` — Environment Detection & Execution

**Trigger**: Invoked by `verdi-debug` orchestrator before any pynpi code execution.

**Content**:
- Verdi installation paths on NVIDIA systems (`/home/tools/debussy/`)
- Version detection algorithm
- Environment variable setup (`VERDI_HOME`, `LD_LIBRARY_PATH`, `PYTHONPATH`)
- Python execution boilerplate template
- Common environment issues and troubleshooting:
  - `_npisys` import failures → LD_LIBRARY_PATH wrong
  - Python version mismatch → must use Verdi's bundled Python 3.11
  - License issues → SNPSLMD_LICENSE_FILE
- `verdi_exec.sh` usage

### 4.2 `verdi-waveform` — FSDB Waveform API

**Trigger**: When AI needs to read waveform data from FSDB files.

**Content** (complete API reference):

#### Module: `pynpi.waveform`

**File Operations:**
- `waveform.open(name)` → FileHandle or None
- `file.close()`
- File properties: `name()`, `scale_unit()`, `min_time()`, `max_time()`, `dump_off_range()`, `version()`, `sim_date()`, `has_glitch()`, `has_assertion()`, `has_force_tag()`, `has_reason_code()`

**Scope Traversal:**
- `file.top_scope()` → Scope
- `scope.name()`, `scope.full_name()`, `scope.def_name()`, `scope.type()`
- `scope.parent()` → Scope
- `scope.child_scope_list()` → [Scope]
- `scope.sig_list()` → [Signal]

**Signal Properties:**
- `sig.name()`, `sig.full_name()`, `sig.direction()`, `sig.left_range()`, `sig.right_range()`
- `sig.is_real()`, `sig.is_string()`, `sig.has_member()`, `sig.is_packed()`
- `sig.composite_type()`, `sig.assertion_type()`, `sig.power_type()`
- `sig.has_reason_code()`, `sig.reason_code()`, `sig.reason_code_desc()`
- `sig.has_force_tag()`, `sig.has_enum()`
- `sig.scope()` → Scope, `sig.parent_sig()` → Signal
- `sig.member_list()` → [Signal]

**Value Change Traverse (VCT):**
- `sig.create_vct()` → VCT
- `vct.time()`, `vct.value(format)`, `vct.format()`, `vct.seq_num()`
- `vct.goto_next()`, `vct.goto_prev()`, `vct.goto_first()`, `vct.goto_time(time)`
- `vct.duration()`, `vct.sig()`, `vct.release()`
- **CRITICAL**: Must call `vct.release()` when done.

**Force Tag Traverse (FT):**
- `sig.create_ft()` → FT
- `ft.time()`, `ft.value()`, `ft.goto_next()`, `ft.goto_prev()`, `ft.goto_first()`, `ft.goto_time(time)`, `ft.release()`

**VC Iterator (high-performance batch):**
- Time-Based: `waveform.TimeBasedVcIterator()`
  - `add(signal, filterEq=False)`, `iter_start(begin, end)`, `iter_next()`, `iter_stop()`, `get_value(format)`, `set_max_session_load(num)`
- Signal-Based: `waveform.SignalBasedVcIterator()`
  - Same interface, different traversal order

**L1 Convenience APIs:**
- `waveform.sig_value_at(file, sigName, time, format)` → value
- `waveform.sig_hdl_value_at(sig, time, format)` → value
- `waveform.sig_vec_value_at(file, sigNameList, time, format)` → [value]
- `waveform.sig_value_between(file, sigName, begin, end, format)` → [(time, value)]
- `waveform.sig_hdl_value_between(sig, begin, end, format)` → [(time, value)]
- `waveform.dump_sig_value_between(file, sigName, begin, end, outFile, format)`
- `waveform.hier_tree_dump_scope(file, outFile, rootScope=None)`
- `waveform.hier_tree_dump_sig(file, outFile, rootScope=None, expand=0)`
- `waveform.time_scale_unit(file)` → string
- `waveform.convert_time_in(file, timeValue, timeUnit)` → int
- `waveform.convert_time_out(file, timeValue, timeUnit)` → float

**Enums:**
- `VctFormat_e`: BinStrVal(0), OctStrVal(1), DecStrVal(2), HexStrVal(3), SintVal(4), UintVal(5), RealVal(6), StringVal(7), EnumStrVal(8), Sint64Val(9), Uint64Val(10), ObjTypeVal(11)
- `ScopeType_e`: SvModule(0)..Unknown(27)
- `DirType_e`: DirNone(0), DirInput(1), DirOutput(2), DirInout(3)
- `SigAssertionType_e`: Assert(0), Assume(1), Cover(2), Restrict(3), Unknown(4)
- `SigCompositeType_e`: Array(0), Struct(1), Union(2), TaggedUnion(3), Record(4), ClassObject(5), DynamicArray(6), QueueArray(7), AssociativeArray(8)
- `ForceTag_e`: InitialForce(0), Force(1), Release(2), Deposit(3), Unknown(4)
- `ForceSource_e`: Design(0), External(1), Unknown(2)

**X-Value Search (CRITICAL for X-propagation RCA):**
- `waveform.sig_find_x_forward(file, sigName, beginTime, format)` → (time, value) or None
- `waveform.sig_find_x_backward(file, sigName, beginTime, format)` → (time, value) or None
- `waveform.sig_hdl_find_x_forward(sig, beginTime, format)` → (time, value) or None
- `waveform.sig_hdl_find_x_backward(sig, beginTime, format)` → (time, value) or None

**Value Search:**
- `waveform.sig_find_value_forward(file, sigName, value, beginTime, format, zeroExtension=False)` → time or None
- `waveform.sig_find_value_backward(file, sigName, value, beginTime, format, zeroExtension=False)` → time or None
- `waveform.sig_vc_count(file, sigName, beginTime, endTime)` → int (count of value changes)

**Expression Evaluator (SystemVerilog expressions over time):**
- `eval = waveform.SigValueEval()`
- `eval.set_wave(file)`, `eval.set_expr(expr)`, `eval.set_time(begin, end)`
- `eval.evaluate(timeValueMode=False)` → [rc, trueTimeList, falseTimeList]
- `eval.get_edge()` / `eval.get_posedge()` / `eval.get_negedge()`

**Memory Management (IMPORTANT for large FSDB):**
- `file.add_to_sig_list(signal)` — add signal to pending load list
- `file.load_vc_by_range(start, end)` — load VCs for time range (reduces memory)
- `file.unload_vc()` — free loaded VCs
- `file.reset_sig_list()` — clear pending list

**Additional File Info:**
- `waveform.is_fsdb(name)` → bool — check if file is FSDB
- `waveform.info(name)` → dict — get file metadata

**Usage Patterns:**
- Quick signal check: `sig_value_at()` for single point
- Time range analysis: `sig_value_between()` for value history
- Bulk analysis: `TimeBasedVcIterator` for multi-signal snapshots
- Edge detection: VCT `goto_time()` + `goto_next()` loop, or `SigValueEval.get_edge()`
- X-prop debug: `sig_find_x_forward/backward()` to locate X sources
- Performance: Use `load_vc_by_range()` for memory control; use iterators for large ranges; use `sig_value_at` for spot checks

### 4.3 `verdi-coverage` — VDB Coverage API

**Trigger**: When AI needs to analyze coverage data from VDB.

**Content** (complete API reference):

#### Module: `pynpi.cov`

**Database Operations:**
- `cov.open(name)` → Database or None
- `db.close()`, `db.name()`, `db.type()`
- `db.test_handles()` → [Test]
- `db.instance_handles()` → [Instance]
- `db.handle_by_name(name)`, `db.test_by_name(name)`

**Test Management:**
- `cov.merge_test(test1, test2)` → merged Test
- `test.save_test(name)`, `test.unload_test()`
- `test.load_exclude_file(name)`, `test.save_exclude_file(name, mode)`, `test.unload_exclusion()`
- `test.assert_metric_handle()`, `test.testbench_metric_handle()`
- `test.test_info_handles()`, `test.program_handles()`, `test.power_data_handles()`

**Instance Hierarchy:**
- `inst.instance_handles()` → [Instance] (children)
- `inst.database_handle()` → Database
- `inst.scope_handle()` → Scope
- Metric accessors:
  - `inst.line_metric_handle()`
  - `inst.toggle_metric_handle()`
  - `inst.fsm_metric_handle()`
  - `inst.condition_metric_handle()`
  - `inst.branch_metric_handle()`
  - `inst.assert_metric_handle()`

**Coverage Metric (common interface for all metric handles):**
- Identity: `name()`, `type()`, `line_no()`
- Coverage data: `covered(test)`, `coverable(test)`, `count(test)`, `count_goal(test)`, `size(test)`
- Status queries: `status(test)`, `has_status_covered(test)`, `has_status_excluded(test)`, `has_status_unreachable(test)`, `has_status_illegal(test)`, `has_status_proven(test)`, `has_status_attempted(test)`, `has_status_excluded_at_compile_time(test)`, `has_status_excluded_at_report_time(test)`, `has_status_partially_excluded(test)`, `has_status_partially_attempted(test)`
- Status setters: `set_status_covered()`, `set_status_excluded()`, `set_status_unreachable()`, etc.
- Properties: `per_instance(test)`, `is_mda(test)`, `is_port(test)`, `is_event_condition(test)`, `severity(test)`, `category(test)`
- Hierarchy: `child_handles()` → sub-metrics/bins

**Config Options (for opening VDB):**
- `cov.ConfigOpt.ExclusionInStrictMode` — strict exclusion mode
- `cov.ConfigOpt.ExcludeByStmtLevel` — statement-level exclusion
- `cov.ConfigOpt.LimitedDesign` — no design hierarchy (faster load)
- `cov.ConfigOpt.NoLoadMetricData` — skip metric data (faster load)
- Usage: `cov.open("simv.vdb", cov.ConfigOpt.LimitedDesign | cov.ConfigOpt.NoLoadMetricData)`

**Assertion Coverage Report:**
- `cov.report_assert_coverage(db, file_name, is_hier_view=True, is_show_all=True, is_merge_tests=True)` → bool

**Resource Management:**
- `cov.release_handle(hdl)` — **CRITICAL**: must release all handles when done

**Usage Patterns:**
- Coverage summary: traverse instances, collect covered/coverable for each metric type
- Gap analysis: find bins where `has_status_covered() == False`
- Multi-test merge: `merge_test()` before querying for aggregate view
- Exclusion handling: load exclusions before coverage queries for accurate numbers
- Fast load: use `ConfigOpt.LimitedDesign` when only testbench coverage is needed

### 4.4 `verdi-netlist` — Netlist Traversal & Signal Tracing

**Trigger**: When AI needs to trace signal connectivity or understand design hierarchy.

**Content** (API reference for `pynpi.netlist`):

#### Module: `pynpi.netlist`

**Enums:**
- `ObjectType`: INST, PORT, INSTPORT, DECL_NET, CONCAT_NET, SLICE_NET, PSEUDO_PORT, PSEUDO_INSTPORT, PSEUDO_NET, LIB, CELL, CELLPIN
- `FuncType`: SIG_TO_SIG, FAN_IN, FAN_OUT
- `ValueFormat`: BIN, OCT, HEX, DEC

**Handle Retrieval:**
- `netlist.get_inst(name)` → InstHdl
- `netlist.get_port(name)` → PinHdl
- `netlist.get_instport(name)` → PinHdl
- `netlist.get_net(name)` → NetHdl
- `netlist.get_top_inst_list()` → [InstHdl]
- `netlist.get_actual_net(name)` → NetHdl

**InstHdl (Instance):**
- `inst_list()` → [InstHdl] — child instances
- `net_list()` → [NetHdl] — internal nets
- `port_list()` → [PinHdl] — ports
- `instport_list()` → [PinHdl] — instance ports
- `driver_instport_list()` → [PinHdl] — driver instports
- `load_instport_list()` → [PinHdl] — load instports
- Properties: `name()`, `full_name()`, `def_name()`, `lang_type()`, `cell_type()`, `inst_type()`, `src_info()`, `file()`, `begin_line_no()`, `end_line_no()`, `is_interface()`, `is_memory_cell()`, `is_pad_cell()`

**PinHdl (Port/InstPort):**
- `connected_pin()` → PinHdl, `connected_net()` → NetHdl
- `driver_list()` → [PinHdl], `load_list()` → [PinHdl]
- Properties: `name()`, `full_name()`, `direction()`, `size()`, `left()`, `right()`, `port_type()`

**NetHdl (Net):**
- `driver_list()` → [PinHdl] — **key for driver tracing**
- `load_list()` → [PinHdl] — **key for load tracing**
- `fan_in_reg_list()` → register fan-in chain
- `fan_out_reg_list()` → register fan-out chain
- `to_sig_conn_list(to_hdl, assign_cell=False)` → signal-to-signal connections
- Properties: `name()`, `full_name()`, `net_type()`, `size()`, `left()`, `right()`, `value(format)`

**Hierarchy Traversal:**
- `netlist.hier_tree_trv(scope_hier_name=None)` — traverse with callbacks
- `netlist.hier_tree_trv_register_cb(obj_type, cb_func, cb_data)`
- `netlist.sig_to_sig_conn_list(from_hdl, to_hdl, assign_cell=False)` — trace connectivity

**Usage Patterns:**
- Driver trace: `net.driver_list()` → through hierarchy → to source driver
- Load trace: `net.load_list()` → fan-out → all consumers
- Register-to-register: `net.fan_in_reg_list()` / `net.fan_out_reg_list()`
- Cross-hierarchy: `sig_to_sig_conn_list()` for full path

### 4.5 `verdi-language` — RTL Source Model

**Trigger**: When AI needs to trace signals through RTL, correlate waveform with source code, or find design constructs.

**Content** (API reference for `pynpi.lang`):

#### Module: `pynpi.lang`

**Signal Tracing (CRITICAL for RCA):**
- `lang.trace_driver2(sig_hier_name, is_pass_thr=True, bnd_hdl_list=None, trc_opt=None)` → [handles] — **trace all drivers of a signal**
- `lang.trace_driver_by_hdl2(sig_hdl, ...)` → [handles] — same, by handle
- `lang.trace_load2(sig_hier_name, ...)` → [handles] — **trace all loads**
- `lang.trace_load_by_hdl2(sig_hdl, ...)` → [handles]
- `lang.trace_driver_dump2(sig_hier_name, file, ...)` — dump trace to file
- `lang.trace_load_dump2(sig_hier_name, file, ...)` — dump trace to file

**Active Tracing (time-aware, for RCA):**
- `lang.active_trace_driver(sig_hier_name, time, trc_opt=None)` → [ActTrcRes] — **trace active driver at specific time**
- `lang.active_trace_driver_by_hdl(sig_hdl, time, ...)` → [ActTrcRes]
- `lang.active_trace_driver_dump(sig_hier_name, file, time, ...)` — dump to file

**Hierarchy & Search:**
- `lang.get_top_inst_list()` → [handles]
- `lang.handle_by_name(name, hdl)` → handle
- `lang.hier_tree_trv(scope_hier_name=None, depth=0)` — traverse with callbacks
- `lang.hier_tree_dump_txt(root_scope, file)` — dump hierarchy to text
- `lang.hier_tree_dump_csv(root_scope, file, is_skip_lib_cell=False)` — dump to CSV

**Pattern Matching (find instances/signals):**
- `lang.find_inst_wildcard(scope_name, inst_wildcard_list)` → [handles]
- `lang.find_inst_regex(scope_name, inst_regex_list)` → [handles]
- `lang.find_signal_wildcard(scope_name, signal_wildcard_list)` → [handles]
- `lang.find_signal_regex(scope_name, signal_regex_list)` → [handles]

**Source Info:**
- `lang.get_signal_define_typespec(sig_hier_name)` → type string
- `lang.get_hdl_info(hdl, isComposeFullName, getConstSize)` → info string
- `lang.verbose_dump(hdl, file, verbose)` — detailed dump
- `lang.expr_decompile(hdl, constSize, resConstOpr)` → expression string

**TrcOption class** (trace options):
- `set_scope_hdl()`, `set_is_pass_thr()`, `set_is_force()`, `set_active_time()`
- `set_edge_check()`, `set_show_flatten()`, `set_ignore_port_dir()`

**Usage Patterns:**
- From waveform signal → `lang.trace_driver2()` → find RTL driver chain
- At failure time → `lang.active_trace_driver(sig, time)` → find which driver was active
- Find all instances matching pattern → `lang.find_inst_regex()`
- Get signal type → `lang.get_signal_define_typespec()`

### 4.6 `verdi-transaction` — Transaction Waveform

**Trigger**: When AI needs to analyze transaction-level waveforms (bus protocols, messages).

**Content** (API reference for transaction waveform in `pynpi.waveform`):

**Transaction scope/stream access (on FileHandle):**
- `file.top_tr_scope_list()` → [TrScopeHandle]
- `file.tr_scope_by_name(name)` → TrScopeHandle
- `file.stream_by_name(name)` → StreamHandle
- `file.add_to_stream_list(stream)`, `file.reset_stream_list()`
- `file.load_trans()` / `file.unload_trans()` — memory management
- `file.trt_by_id(id)` → TrtHandle
- `file.relation_list()` → [RelationHandle]

**TrScopeHandle:** `name()`, `full_name()`, `child_tr_scope_list()`, `stream_list()`, `attr_count()`, `attr_name(i)`, `attr_value(i, format)`

**StreamHandle:** `name()`, `full_name()`, `create_trt()` → TrtHandle, `attr_count()`, `attr_name(i)`, `attr_value(i, format)`

**TrtHandle (Transaction Traverse):**
- `id()`, `name()`, `time()` → [begin, end], `type()` → TrtType_e
- `goto_first()`, `goto_next()`, `goto_prev()`, `goto_time(time)`
- `attr_count()`, `attr_name(i)`, `attr_value(i, format)`
- `related_trt_list(relation, direction)` — master/slave relationships
- `call_stack_count(type)`, `call_stack(i, type)` → [file, line]
- `is_unfinished()`, `release()`

**Protocol Extraction (L1 — built into waveform module):**
- `waveform.ProtocolExtractor(protocol)` — APB/AHB/AXI protocol grouping
- `waveform.MessageExtractor2()` — message extraction with iteration

**Enums:** `RelationDirType_e` (Master/Slave), `CallStackType_e` (Begin/End), `TrtType_e` (Message/Transaction/Action/Group), `Protocol_e` (APB/AHB/AXI)

**Usage Patterns:**
- AXI/AHB/APB bus transaction analysis
- Protocol violation detection (ordering, timing)
- Transaction-to-waveform time correlation
- Message log correlation with signal activity

### 4.7 `verdi-rca` — Root Cause Analysis Methodology

**Trigger**: Invoked by `verdi-debug` orchestrator to guide the investigation strategy.

**Content** (not API — pure methodology):

#### RCA Framework

**Phase 1: Error Log Parsing**
- Extract key information:
  - Failure timestamp (simulation time)
  - Error type (timeout, assertion, data mismatch, protocol violation, X-prop)
  - Signal/scope names mentioned
  - Expected vs. actual values
  - Test name and seed
- Classify error type to determine investigation strategy

**Phase 2: Initial Reconnaissance**
- Open FSDB, verify scope hierarchy matches error log references
- Check time range: is failure time within FSDB dump window?
- Sample key signals at/around failure time
- If VDB available: check coverage of relevant instances

**Phase 3: Hypothesis Generation**

| Error Type | Typical Hypotheses | First Signals to Check |
|---|---|---|
| Assertion failure | Precondition violated, design bug, missing constraint | Assertion signals, trigger conditions |
| Data mismatch | Incorrect computation, wrong mux select, stale data | Data path, select lines, enable signals |
| Timeout/hang | FSM stuck, handshake deadlock, clock gating | State machine signals, handshake pairs, clocks |
| X-propagation | Uninitialized reg, floating wire, power domain issue | X source signal, reset, initialization sequence |
| Protocol violation | Missing handshake, wrong ordering, timing violation | Protocol control signals (valid/ready, req/ack) |

**Phase 4: Hypothesis Verification Loop**

```
for each hypothesis:
  1. Identify signals to check (from netlist trace or domain knowledge)
  2. Query waveform values at relevant times
  3. Does evidence support or refute this hypothesis?
  4. If supported: trace deeper (find root cause in driver chain)
  5. If refuted: move to next hypothesis
  6. If ambiguous: gather more data (wider time range, more signals)
```

**Phase 5: Causal Chain Construction**
- Once root cause identified, build full chain:
  `Root cause signal @ time → intermediate effect → ... → observed failure`
- Verify each link in the chain with waveform evidence

**Phase 6: Report**
- Root cause: signal, time, condition
- Causal chain with evidence
- Relevant coverage gaps (if VDB available)
- Suggested fix direction

#### Common Debug Recipes

**When to stop tracing:**
- If 3+ levels of driver chain traced without finding clear cause → escalate to user
- If signal trace leads outside FSDB dump scope → report boundary and ask user for guidance
- If multiple equally plausible hypotheses remain → present top 2-3 with evidence to user

**Clock/Reset Issues:**
1. Check clock: `waveform.sig_value_between(f, "clk", t-100, t+100, waveform.VctFormat_e.BinStrVal)`
2. Check reset: `waveform.sig_value_at(f, "rst_n", t, waveform.VctFormat_e.BinStrVal)`
3. Look for glitches: check `file.has_glitch()`

**FSM Stuck:**
1. Find state signal: look for `state`, `fsm`, `cs`, `ns` in signal names
2. Check state transitions around failure time
3. Identify last valid transition → what prevented next transition?

**Data Path Debug:**
1. Start at output signal showing wrong value
2. Trace driver through netlist
3. Check each intermediate signal at failure time
4. Find first signal in chain with correct value → next one is wrong → bug is in between

**X-Propagation (enhanced with sig_find_x APIs):**
1. Find signal with X value: `waveform.sig_find_x_backward(f, sig, failure_time, fmt)` to locate when X first appeared
2. Use `waveform.sig_find_x_forward(f, sig, 0, fmt)` to find earliest X in the signal
3. Use `lang.active_trace_driver(sig, x_time)` to trace which driver was active when X appeared
4. Repeat for each driver in the chain until originating X source found
5. Check reset/initialization sequence around X origin time

### 4.8 `verdi-debug` — Orchestrator

**Trigger description**: "Use when user provides FSDB/VDB waveform files, simulation error logs, or asks to debug/analyze hardware simulation results. Trigger on keywords: fsdb, vdb, waveform, debug, trace, signal, coverage, simulation error, RCA, root cause."

**Orchestration Flow:**

```
User provides: FSDB path + error log (+ optional VDB path)
    │
    ▼
[1] Invoke verdi-env: detect Verdi version, verify environment
    │
    ▼
[2] Invoke verdi-rca: parse error log, classify error, plan investigation
    │
    ▼
[3] Invoke verdi-waveform: open FSDB, initial signal reconnaissance
    │
    ├── If VDB provided ──▶ Invoke verdi-coverage: coverage gap analysis
    │
    ▼
[4] Hypothesis loop (AI-driven):
    │   - Generate hypotheses based on error type
    │   - For each hypothesis:
    │     - Use verdi-waveform for value queries
    │     - Use verdi-netlist for signal tracing (if needed)
    │     - Use verdi-language for RTL correlation (if needed)
    │     - Use verdi-transaction for protocol analysis (if needed)
    │   - Verify or refute each hypothesis
    │
    ▼
[5] Build causal chain, report findings
```

**Key Principles (encoded in skill):**
- AI decides which APIs to call — no fixed script
- Each investigation step = dynamically generated Python code
- AI must show waveform evidence for conclusions
- Support iterative dialogue: user can redirect investigation
- All pynpi code must include proper `npisys.init()` / `npisys.end()` and resource cleanup

## 5. `verdi_exec.sh` — Detailed Design

```bash
#!/bin/bash
# verdi_exec.sh — Execute Python code with Verdi NPI environment
#
# Usage:
#   verdi_exec.sh [--verdi-home <path>] [--timeout <secs>] <script.py> [args...]
#   echo "python code" | verdi_exec.sh [--verdi-home <path>] [--timeout <secs>]
#
# Verdi version detection (if --verdi-home not specified):
#   1. $VERDI_HOME environment variable
#   2. Latest stable version in /home/tools/debussy/verdi3_*
#      (excludes Beta, sorts by version string)

set -euo pipefail

VERDI_HOME_ARG=""
TIMEOUT=120
SCRIPT=""
SCRIPT_ARGS=()

# Parse our arguments (stop at first non-option = script path)
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
            SCRIPT_ARGS=("$@")  # Remaining args forwarded to the Python script
            break
            ;;
    esac
done

# Detect Verdi home
if [[ -n "$VERDI_HOME_ARG" ]]; then
    VERDI_HOME="$VERDI_HOME_ARG"
elif [[ -n "${VERDI_HOME:-}" ]]; then
    VERDI_HOME="$VERDI_HOME"
else
    # Auto-detect: latest stable version (exclude Beta, sort full path with -V)
    VERDI_HOME=$(ls -d /home/tools/debussy/verdi3_20* 2>/dev/null \
        | grep -vi beta \
        | sort -V \
        | tail -1)
    if [[ -z "$VERDI_HOME" ]]; then
        echo "ERROR: No Verdi installation found" >&2
        exit 1
    fi
fi

# Verify Verdi installation
PYTHON="${VERDI_HOME}/platform/linux64/python-3.11/bin/python3"
if [[ ! -x "$PYTHON" ]]; then
    echo "ERROR: Python 3.11 not found at ${PYTHON}" >&2
    exit 1
fi

# Warn about license
if [[ -z "${SNPSLMD_LICENSE_FILE:-}" ]] && [[ -z "${LM_LICENSE_FILE:-}" ]]; then
    echo "WARNING: SNPSLMD_LICENSE_FILE not set — NPI may fail with license errors" >&2
fi

# Set environment
export VERDI_HOME
export LD_LIBRARY_PATH="${VERDI_HOME}/share/NPI/lib/linux64:${VERDI_HOME}/platform/linux64/bin:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="${VERDI_HOME}/share/NPI/python:${PYTHONPATH:-}"

echo "Using Verdi: ${VERDI_HOME}" >&2

# Execute with timeout
if [[ -n "$SCRIPT" ]]; then
    timeout "$TIMEOUT" "$PYTHON" "$SCRIPT" "${SCRIPT_ARGS[@]}"
else
    # Read from stdin — create temp file, clean up on exit
    TMPSCRIPT=$(mktemp /tmp/verdi_exec_XXXXXX.py)
    trap 'rm -f "$TMPSCRIPT"' EXIT
    cat > "$TMPSCRIPT"
    timeout "$TIMEOUT" "$PYTHON" "$TMPSCRIPT"
fi
```

## 6. plugin.json

**Note**: `plugin.json` evolves with each phase. Only reference skill files that actually exist. Create placeholder stubs for deferred skills with a single line: `<!-- Deferred to Phase N -->`.

**Phase 1 (MVP):**
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

**Phase 2:** Add `skills/verdi-coverage.md`
**Phase 3 (full):** Add `skills/verdi-netlist.md`, `skills/verdi-language.md`, `skills/verdi-transaction.md`

## 7. Known Limitations

### Phase 1 Limitations
- **No netlist tracing**: Cannot trace signal drivers/loads. AI must rely on signal naming conventions and user guidance for causal analysis.
- **No RTL source correlation**: Cannot map waveform signals to RTL source lines.
- **No transaction analysis**: Cannot parse transaction-level waveforms.
- **No coverage analysis**: VDB support deferred to Phase 2.
- The `verdi-debug` orchestrator must gracefully skip netlist/language/transaction steps and note what it cannot do.

### General Limitations
- Requires Verdi 2025.06+ for Python 3.11 NPI bindings (older versions have only C/Tcl NPI)
- `pynpi` API may differ across Verdi versions — skills are documented against `verdi3_2025.06-SP2-2`
- All NPI handles (`vct`, `ft`, coverage handles) must be manually released — leaked handles cause memory issues
- Large FSDB files may cause slow queries; AI should use iterators for bulk operations and `sig_value_at` for spot checks
- Synopsys license (`SNPSLMD_LICENSE_FILE`) must be available in the environment

## 8. Implementation Plan

### Phase 1: Core (MVP)
1. `plugin.json` — manifest (Phase 1 version)
2. `verdi_exec.sh` — environment bootstrap
3. `verdi-env.md` — environment detection skill
3. `verdi-waveform.md` — FSDB waveform API skill (most critical)
4. `verdi-rca.md` — RCA methodology
5. `verdi-debug.md` — orchestrator
6. `plugin.json`

### Phase 2: Coverage
7. `verdi-coverage.md` — VDB coverage API skill

### Phase 3: Full Capability
8. `verdi-netlist.md` — netlist traversal
9. `verdi-language.md` — RTL source model
10. `verdi-transaction.md` — transaction waveform

### Phase 4: Refinement
- Test with real FSDB/VDB files
- Iterate on RCA methodology based on actual debug sessions
- Add more debug recipes to `verdi-rca.md`
- Optimize skill descriptions for better triggering accuracy
