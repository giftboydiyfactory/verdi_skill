---
name: verdi-language
version: 0.1.0
description: "This skill should be used when the user asks to 'trace signal driver in RTL', 'find source file location', 'active trace at time', 'find signals by pattern', or needs RTL source analysis via KDB. Provides the pynpi.lang API reference."
---

# pynpi.lang API Reference

## 1. Quick Start

```python
from pynpi import npisys, lang
npisys.init(sys.argv)
npisys.load_design(sys.argv)  # Need RTL source files
# Trace drivers of a signal
drivers = lang.trace_driver2("top.cpu.data_out")
for drv in drivers:
    print(lang.get_hdl_info(drv, True, False))
npisys.end()
```

**Note:** `lang` requires `npisys.load_design()` with RTL source files.

## 2. Signal Tracing (CRITICAL for RCA)

### Static tracing (all possible drivers)

```python
lang.trace_driver2(sig_hier_name, is_pass_thr=True, bnd_hdl_list=None, trc_opt=None) -> [handles]
lang.trace_driver_by_hdl2(sig_hdl, is_pass_thr=True, ...) -> [handles]
lang.trace_load2(sig_hier_name, is_pass_thr=True, ...) -> [handles]
lang.trace_load_by_hdl2(sig_hdl, ...) -> [handles]
```

Dump to file:

```python
lang.trace_driver_dump2(sig_hier_name, file, ...) -> int
lang.trace_load_dump2(...) -> int
```

### Active tracing (time-aware -- KEY for RCA)

```python
lang.active_trace_driver(sig_hier_name, time, trc_opt=None) -> [ActTrcRes]
lang.active_trace_driver_by_hdl(sig_hdl, time, ...) -> [ActTrcRes]
lang.active_trace_driver_dump(sig_hier_name, file, time, ...) -> int
```

`ActTrcRes` attributes:
- `result.get_hdl()` -> handle
- `result.get_active_time()` -> int

## 3. Hierarchy & Scope

### Handle management

```python
lang.get_top_inst_list() -> [handles]
lang.handle_by_name(name, hdl) -> handle
lang.handle_by_index(hdl, index) -> handle
lang.handle_by_range(hdl, left, right) -> handle
lang.release_handle(hdl) -> int
lang.release_all_handles() -> int
```

### Hierarchy traversal

```python
lang.hier_tree_trv(scope_hier_name=None, depth=0) -> int
lang.hier_tree_trv_register_cb(obj_type, cb_func, cb_data) -> int
lang.hier_tree_trv_reset_cb() -> int
lang.hier_tree_dump_txt(root_scope, file) -> int
lang.hier_tree_dump_csv(root_scope, file, is_skip_lib_cell=False) -> int
```

## 4. Pattern Matching (Find instances/signals)

### Instance matching

```python
lang.find_inst_wildcard(scope_name, inst_wildcard_list) -> [handles]
lang.find_inst_regex(scope_name, inst_regex_list) -> [handles]
```

### Signal matching

```python
lang.find_signal_wildcard(scope_name, signal_wildcard_list) -> [handles]
lang.find_signal_regex(scope_name, signal_regex_list) -> [handles]
```

### Dump variants

```python
lang.find_inst_wildcard_dump(...) -> int
lang.find_inst_regex_dump(...) -> int
lang.find_signal_wildcard_dump(...) -> int
lang.find_signal_regex_dump(...) -> int
```

### Definition matching

```python
lang.find_inst_with_def_wildcard(scope_name, def_wildcard_list) -> [handles]
lang.find_inst_with_def_regex(scope_name, def_regex_list) -> [handles]
```

## 5. Source Info

```python
lang.get_signal_define_typespec(sig_hier_name) -> str
lang.get_hdl_info(hdl, isComposeFullName, getConstSize) -> str
lang.verbose_dump(hdl, file, verbose) -> int
lang.expr_decompile(hdl, constSize, resConstOpr) -> str
lang.get_bit_blasted_signal(sig_hdl) -> [handles]
lang.list_all_module_define(root_scope, file) -> int
```

## 6. TrcOption Class

Configuration for trace operations:

```python
trc_opt = lang.TrcOption()

trc_opt.set_is_pass_thr(val)      # / get_is_pass_thr()
trc_opt.set_is_force(val)         # / get_is_force()
trc_opt.set_active_time(time)     # / get_active_time()
trc_opt.set_edge_check(val)       # / get_edge_check()
trc_opt.set_show_flatten(val)     # / get_show_flatten()
trc_opt.set_ignore_port_dir(val)  # / get_ignore_port_dir()
trc_opt.set_scope_hdl(hdl)        # / get_scope_hdl()
```

## 7. Text API (pynpi.text)

Source file reading:

```python
text.get_file_list() -> [File]
text.file_by_name(name) -> File
file.line_handles() -> [Line]
line.line_content() -> str
line.line_number() -> int
line.word_handles() -> [Word]
word.word_name() -> str
word.word_attribute() -> str
```

## 8. SDB API (pynpi.sdb)

Static database:

```python
sdb.get_top_instances() -> Iterator
sdb.get_instance_by_name(name) -> InstanceHdl
inst.master_handle() -> MasterHdl
inst.child_instance_handles() -> Iterator
```

## 9. Common Patterns

**From waveform signal to RTL drivers:**
```python
drivers = lang.trace_driver2(sig_full_name)
```

**At failure time, find which driver is active:**
```python
results = lang.active_trace_driver(sig, time)
for r in results:
    print(lang.get_hdl_info(r.get_hdl(), True, False), "at", r.get_active_time())
```

**Find all state machines:**
```python
fsm_signals = lang.find_signal_regex("top", [".*state.*", ".*fsm.*"])
```

**Get signal type:**
```python
typespec = lang.get_signal_define_typespec(sig_name)
```
