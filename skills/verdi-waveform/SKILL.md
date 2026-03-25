---
name: verdi-waveform
version: 0.1.0
description: "This skill should be used when the user asks to 'read waveform', 'check signal value', 'find X values', 'dump hierarchy', 'trace value changes', or needs to query FSDB waveform data. Provides the complete pynpi.waveform API reference."
---

# pynpi.waveform API Reference

Complete reference for reading FSDB waveform files via `pynpi.waveform`.

## 1. Quick Start

```python
import sys
from pynpi import npisys, waveform

npisys.init([sys.argv[0]])
f = waveform.open("test.fsdb")
val = waveform.sig_value_at(f, "top.clk", 1000, waveform.VctFormat_e.HexStrVal)
print(val)
waveform.close(f)
npisys.end()
```

## 2. File Operations

| Function | Returns | Description |
|----------|---------|-------------|
| `waveform.open(name)` | FileHandle or None | Open an FSDB file |
| `waveform.close(file)` | bool | Close an open FSDB file |
| `waveform.is_fsdb(name)` | bool | Check if a file is FSDB format |
| `waveform.info(name)` | dict | Get file metadata without fully opening |

## 3. FileHandle Properties

Time and identity:

| Method | Returns | Description |
|--------|---------|-------------|
| `file.min_time()` | int | Minimum simulation time |
| `file.max_time()` | int | Maximum simulation time |
| `file.name()` | str | File path |
| `file.scale_unit()` | str | Time scale string (e.g. `"1ns"`) |
| `file.dump_off_range()` | str | Dump off ranges |
| `file.version()` | str | FSDB version |
| `file.sim_date()` | str | Simulation date |

Capability flags:

| Method | Returns | Description |
|--------|---------|-------------|
| `file.has_seq_num()` | bool | Has sequence numbers |
| `file.is_completed()` | bool | Simulation completed normally |
| `file.has_glitch()` | bool | Contains glitch data |
| `file.has_assertion()` | bool | Contains assertion data |
| `file.has_force_tag()` | bool | Contains force/release tags |
| `file.has_reason_code()` | bool | Contains reason codes |
| `file.has_power_info()` | bool | Contains power data |
| `file.has_gate_tech()` | bool | Contains gate technology data |

## 4. Scope Traversal

### FileHandle scope/signal lookup

| Method | Returns | Description |
|--------|---------|-------------|
| `file.top_scope_list()` | [ScopeHandle] | All top-level scopes |
| `file.scope_by_name(name, scope=None)` | ScopeHandle or None | Find scope by hierarchical name; optional root scope |
| `file.top_sig_list()` | [SigHandle] | All top-level signals |
| `file.sig_by_name(name, scope=None)` | SigHandle or None | Find signal by hierarchical name; optional root scope |

### ScopeHandle Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `scope.name()` | str | Scope leaf name |
| `scope.full_name()` | str | Full hierarchical name |
| `scope.def_name()` | str | Definition name (module name) |
| `scope.type(isEnum=True)` | ScopeType_e or str | Scope type |
| `scope.parent()` | ScopeHandle | Parent scope |
| `scope.child_scope_list()` | [ScopeHandle] | Child scopes |
| `scope.sig_list()` | [SigHandle] | Signals in this scope |
| `scope.file()` | FileHandle | Owning file |

## 5. Signal Properties (SigHandle)

### Identity

| Method | Returns | Description |
|--------|---------|-------------|
| `sig.name()` | str | Signal leaf name |
| `sig.full_name()` | str | Full hierarchical name |

### Type queries

| Method | Returns | Description |
|--------|---------|-------------|
| `sig.is_real()` | bool | Analog / real-valued signal |
| `sig.is_string()` | bool | String-typed signal |
| `sig.is_packed()` | bool | Packed array |
| `sig.is_param()` | bool | Parameter / localparam |

### Capability flags

| Method | Returns | Description |
|--------|---------|-------------|
| `sig.has_member()` | bool | Composite signal with sub-members |
| `sig.has_enum()` | bool | Has enum type info |
| `sig.has_force_tag()` | bool | Has force/release data |
| `sig.has_reason_code()` | bool | Has reason code data |

### Range

| Method | Returns | Description |
|--------|---------|-------------|
| `sig.left_range()` | int | Left bit index |
| `sig.right_range()` | int | Right bit index |
| `sig.range_size()` | int | Bit width |

### Classification

| Method | Returns | Description |
|--------|---------|-------------|
| `sig.direction(isEnum=True)` | DirType_e or str | Port direction |
| `sig.assertion_type(isEnum=True)` | SigAssertionType_e or str | Assertion type |
| `sig.composite_type(isEnum=True)` | SigCompositeType_e or str | Composite type (struct, array, etc.) |
| `sig.power_type(isEnum=True)` | SigPowerType_e or str | Power signal type |
| `sig.sp_type(isEnum=True)` | SigSpiceType_e or str | SPICE signal type |
| `sig.reason_code()` | str | Reason code |
| `sig.reason_code_desc()` | str | Reason code description |

### Navigation

| Method | Returns | Description |
|--------|---------|-------------|
| `sig.scope()` | ScopeHandle | Parent scope |
| `sig.parent_sig()` | SigHandle | Parent signal (for members) |
| `sig.file()` | FileHandle | Owning file |
| `sig.member_list()` | [SigHandle] | Sub-members (for composite signals) |

### Iterator creation

| Method | Returns | Description |
|--------|---------|-------------|
| `sig.create_vct()` | VctHandle | Create value change traverse iterator |
| `sig.create_ft()` | FtHandle | Create force tag traverse iterator |

## 6. L1 Convenience APIs (Most Commonly Used)

### Signal value at a specific time

```python
# By name
val = waveform.sig_value_at(file, sigName, time, format=VctFormat_e.BinStrVal)

# By handle
val = waveform.sig_hdl_value_at(sig, time, format=VctFormat_e.BinStrVal)

# Multiple signals by name
vals = waveform.sig_vec_value_at(file, sigNameList, time, format=VctFormat_e.BinStrVal)

# Multiple signals by handle
vals = waveform.sig_hdl_vec_value_at(sigHdlList, time, format=VctFormat_e.BinStrVal)
```

### Signal values over a time range

```python
# Returns list of (time, value) tuples
changes = waveform.sig_value_between(file, sigName, beginTime, endTime,
                                      format=VctFormat_e.BinStrVal)

changes = waveform.sig_hdl_value_between(sig, beginTime, endTime,
                                          format=VctFormat_e.BinStrVal)
```

### Dump signal values to file

```python
ok = waveform.dump_sig_value_between(file, sigName, beginTime, endTime,
                                      outputFileName, format=VctFormat_e.BinStrVal)

ok = waveform.dump_sig_hdl_value_between(sig, beginTime, endTime,
                                          outputFileName, format=VctFormat_e.BinStrVal)
```

### Hierarchy dump

```python
# Dump scope tree to file
waveform.hier_tree_dump_scope(file, outFileName, rootScope=None)

# Dump signal tree to file
waveform.hier_tree_dump_sig(file, outputFileName, rootScope=None, expand=0)
```

### Time conversion

```python
# Get time scale unit string
unit = waveform.time_scale_unit(file)  # e.g. "1ns"

# Convert external time to internal file time units
internal = waveform.convert_time_in(file, timeValue, timeUnit)

# Convert internal file time units to external
external = waveform.convert_time_out(file, timeValue, timeUnit)
```

## 7. Value Change Traverse (VCT)

Low-level iterator for walking value changes on a single signal.

### Create and navigate

```python
sig = f.sig_by_name("top.cpu.state")
vct = sig.create_vct()
```

### VctHandle Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `vct.time()` | int | Current time |
| `vct.value(format=VctFormat_e.ObjTypeVal)` | value | Value in specified format |
| `vct.format()` | VctFormat_e | Default format |
| `vct.seq_num()` | int | Sequence number |
| `vct.port_value()` | [state, s0, s1] or None | Port value components |
| `vct.duration()` | int or None | Duration until next change |
| `vct.sig()` | SigHandle | Owning signal |
| `vct.goto_first()` | bool | Jump to first value change |
| `vct.goto_next()` | bool | Advance to next value change |
| `vct.goto_prev()` | bool | Move to previous value change |
| `vct.goto_time(time)` | bool | Jump to last change at or before `time` |
| `vct.release()` | None | **MUST call when done** |

### Example: iterate over a time window

```python
sig = f.sig_by_name("top.cpu.state")
vct = sig.create_vct()
vct.goto_time(1000)
while vct.goto_next():
    print(f"t={vct.time()} v={vct.value(waveform.VctFormat_e.HexStrVal)}")
    if vct.time() > 2000:
        break
vct.release()  # CRITICAL: always release
```

## 8. Force Tag Traverse (FT)

Iterator for walking force/release events on a signal.

```python
ft = sig.create_ft()
```

### FtHandle Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `ft.time()` | int | Current time |
| `ft.value()` | [ForceTag_e, ForceSource_e, file_name, line_num] | Force tag details |
| `ft.goto_first()` | bool | Jump to first force event |
| `ft.goto_next()` | bool | Advance to next force event |
| `ft.goto_prev()` | bool | Move to previous force event |
| `ft.goto_time(time)` | bool | Jump to last force event at or before `time` |
| `ft.release()` | None | **MUST call when done** |

## 9. VC Iterators (High-Performance Batch)

### TimeBasedHandle

Iterates value changes across multiple signals ordered by time. Efficient for multi-signal analysis over a time range.

```python
it = waveform.TimeBasedHandle()
id_a = it.add(sig_a)  # returns signal ID > 0
id_b = it.add(sig_b)
it.iter_start(begin_time, end_time)
while True:
    result = it.iter_next()  # returns [signal_id, time] or None
    if not result:
        break
    val = it.get_value(waveform.VctFormat_e.HexStrVal)
    print(f"sig={result[0]} t={result[1]} v={val}")
it.iter_stop()
```

### SigBasedHandle

Same interface as TimeBasedHandle, but iterates all changes for one signal before moving to the next. Better for per-signal sweep operations.

### Shared Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `it.add(signal, filterEq=False)` | int (signal ID) | Add signal; `filterEq=True` filters out consecutive equal values |
| `it.iter_start(begin, end)` | None | Start iteration over time range |
| `it.iter_next()` | [signal_id, time] or None | Advance to next value change |
| `it.iter_stop()` | None | Stop iteration |
| `it.get_value(format)` | value | Get value at current position |
| `it.set_max_session_load(num)` | None | Limit concurrent signal loads for memory control |

## 10. X-Value Search (Critical for X-Propagation Debug)

Find the next or previous X (unknown) value on a signal.

| Function | Returns | Description |
|----------|---------|-------------|
| `waveform.sig_find_x_forward(file, sigName, beginTime, format=VctFormat_e.BinStrVal)` | (time, value) or None | First X at or after beginTime |
| `waveform.sig_hdl_find_x_forward(sig, beginTime, format)` | (time, value) or None | Same, by handle |
| `waveform.sig_find_x_backward(file, sigName, beginTime, format)` | (time, value) or None | Last X at or before beginTime |
| `waveform.sig_hdl_find_x_backward(sig, beginTime, format)` | (time, value) or None | Same, by handle |

## 11. Value Search

Find when a signal takes a specific value, or count transitions.

| Function | Returns | Description |
|----------|---------|-------------|
| `waveform.sig_find_value_forward(file, sigName, value, beginTime, format=VctFormat_e.BinStrVal, zeroExtension=False)` | time or None | First match at or after beginTime |
| `waveform.sig_find_value_backward(file, sigName, value, beginTime, format, zeroExtension=False)` | time or None | Last match at or before beginTime |
| `waveform.sig_vc_count(file, sigName, beginTime, endTime)` | int | Number of value changes in range |

## 12. Expression Evaluator (SystemVerilog Expressions Over Time)

Evaluate arbitrary SystemVerilog expressions over waveform data.

```python
eval = waveform.SigValueEval()
eval.set_wave(f)
eval.set_expr("sig_a & sig_b")
eval.set_time(begin, end)

# Boolean evaluation: when is the expression true/false?
rc, true_times, false_times = eval.evaluate()

# Edge detection on the expression result
rc, edges = eval.get_edge()              # (rc, combined_edge_list) — all edges
rc, posedges = eval.get_posedge()        # (rc, posedge_list) — rising edges only
rc, negedges = eval.get_negedge()        # (rc, negedge_list) — falling edges only
# NOTE: get_edge() always returns combined edges. Use get_posedge()/get_negedge() for separate lists.
```

- `rc` is a `WaveL1RC_e` return code (0 = SUCCESS).
- `true_times` / `false_times` are lists of time values.
- `posedges` / `negedges` are lists of time values where rising/falling edges occur.

## 13. Memory Management (IMPORTANT for Large FSDB)

For very large FSDB files, load only the required value changes.

| Method | Returns | Description |
|--------|---------|-------------|
| `file.add_to_sig_list(signal)` | bool | Add a signal to the pending load list |
| `file.reset_sig_list()` | bool | Clear the pending load list |
| `file.load_vc_by_range(start, end)` | bool | Load VCs for signals in list, time range only |
| `file.unload_vc()` | bool | Free all loaded VCs |

### Workflow

```python
f = waveform.open("large.fsdb")
sig = f.sig_by_name("top.data_bus")

# Only load VCs for the time window of interest
f.add_to_sig_list(sig)
f.load_vc_by_range(5000, 10000)

vct = sig.create_vct()
vct.goto_time(5000)
while vct.goto_next():
    if vct.time() > 10000:
        break
    print(vct.value(waveform.VctFormat_e.HexStrVal))
vct.release()

f.unload_vc()  # Free memory
waveform.close(f)
```


---

## Additional Resources

### Reference Files

For enum values, usage patterns, and common pitfalls, consult:

- **`references/enums-and-patterns.md`** — All enum values (VctFormat_e, ScopeType_e, DirType_e, etc.), decision tree for API selection, and common pitfalls to avoid
