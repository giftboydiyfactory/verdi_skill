---
name: verdi-transaction
description: "Transaction waveform API reference for analyzing bus protocols (AXI/AHB/APB), messages, and transaction-level activity in FSDB files — stream traversal, transaction attributes, master/slave relations, protocol extraction. Use when analyzing transaction-level waveforms or bus protocol activity."
---

# Transaction Waveform API

Transaction waveforms in FSDB represent higher-level protocol activity (bus transactions, messages, actions) layered on top of signal-level waveforms. Access them through the `pynpi.waveform` module.

## Quick Start

```python
from pynpi import npisys, waveform
npisys.init([sys.argv[0]])
f = waveform.open("test.fsdb")

# Discover transaction scopes and streams
tr_scopes = f.top_tr_scope_list()
for trs in tr_scopes:
    for stream in trs.stream_list():
        f.add_to_stream_list(stream)

f.load_trans()  # MUST call before accessing transactions

stream = f.stream_by_name("$trans_root.axi_stream")
if stream:
    trt = stream.create_trt()
    if trt and trt.goto_first():
        while True:
            begin, end = trt.time()
            print(f"id={trt.id()} [{begin}-{end}] name={trt.name()}")
            for i in range(trt.attr_count()):
                print(f"  {trt.attr_name(i)} = {trt.attr_value(i)}")
            if not trt.goto_next():
                break
        trt.release()  # MUST release

f.unload_trans()
waveform.close(f)
npisys.end()
```

## FileHandle Transaction Methods

| Method | Returns | Description |
|--------|---------|-------------|
| `file.top_tr_scope_list()` | [TrScopeHandle] | Top-level transaction scopes |
| `file.tr_scope_by_name(name, trScope=None)` | TrScopeHandle or None | Find scope by name |
| `file.stream_by_name(name, trScope=None)` | StreamHandle or None | Find stream by name |
| `file.add_to_stream_list(stream)` | bool | Add stream to pending load list |
| `file.reset_stream_list()` | bool | Clear pending stream list |
| `file.load_trans()` | bool | **MUST call before accessing transactions** |
| `file.unload_trans()` | bool | **MUST call when done** |
| `file.trt_by_id(id)` | TrtHandle or None | Get transaction by unique ID |
| `file.relation_list()` | [RelationHandle] | All defined relations |

**Lifecycle**: `add_to_stream_list()` → `load_trans()` → access → `unload_trans()` → `reset_stream_list()`

## TrScopeHandle

| Method | Returns | Description |
|--------|---------|-------------|
| `name()` | str | Scope name |
| `full_name()` | str | Full hierarchical name |
| `def_name()` | str | Definition name |
| `type(isEnum=True)` | ScopeType_e or str | Scope type |
| `parent()` | TrScopeHandle | Parent scope |
| `child_tr_scope_list()` | [TrScopeHandle] | Child transaction scopes |
| `stream_list()` | [StreamHandle] | Streams in this scope |
| `file()` | FileHandle | Containing file |

**Attributes** (indexed): `attr_count()`, `attr_name(i)`, `attr_value(i, format=ValFormat_e.ObjTypeVal)`, `attr_is_hidden(i)`, `attr_is_tag(i)`, `attr_value_format(i)`

## StreamHandle

| Method | Returns | Description |
|--------|---------|-------------|
| `name()` | str | Stream name |
| `full_name()` | str | Full name |
| `tr_scope()` | TrScopeHandle | Parent scope |
| `create_trt()` | TrtHandle | Create transaction traverse iterator |

Attributes: same interface as TrScopeHandle.

## TrtHandle (Transaction Traverse)

### Identity & Timing

| Method | Returns | Description |
|--------|---------|-------------|
| `id()` | int | Unique transaction ID (-1 on failure) |
| `name()` | str | Transaction name |
| `time()` | [begin, end] | Start and end time as list |
| `type()` | TrtType_e | Message, Transaction, Action, or Group |
| `is_unfinished()` | bool | True if transaction not ended |

### Navigation

| Method | Returns | Description |
|--------|---------|-------------|
| `goto_first()` | bool | Move to first transaction |
| `goto_next()` | bool | Move to next |
| `goto_prev()` | bool | Move to previous |
| `goto_time(time)` | bool | Move to transaction at/before time |

### Attributes

| Method | Returns | Description |
|--------|---------|-------------|
| `attr_count()` | int | Number of attributes |
| `attr_name(ith)` | str | Attribute name |
| `attr_value(ith, format=ValFormat_e.ObjTypeVal)` | value | Value in format |
| `attr_is_hidden(ith)` | bool | Hidden flag |
| `attr_is_tag(ith)` | bool | Tag flag |
| `expected_attr(ith)` | int | Expected attribute index |

### Relations

```python
relations = f.relation_list()
for rel in relations:
    related = trt.related_trt_list(rel, waveform.RelationDirType_e.Slave)
    for r in related:
        print(f"Related: id={r.id()} time={r.time()}")
        r.release()
```

### Call Stack

- `call_stack_count(type=CallStackType_e.Begin)` → int
- `call_stack(ith, type=CallStackType_e.Begin)` → [file, line]

### Cleanup

- `release()` — **MUST call when done**

## RelationHandle

- `name()` → str

## Protocol Extraction

```python
pe = waveform.ProtocolExtractor(waveform.Protocol_e.AXI)
count = pe.extract(f, "top.axi_master", depth=1)
for i in range(count):
    group = pe.get_protocol_group(i)
    if group:
        scope, channel_count, sig_count, ms_type, sig_dict = group
        print(f"Group {i}: {scope.full_name()}, type={ms_type}")
```

### MessageExtractor2

```python
me = waveform.MessageExtractor2()
me.iter_start(f, sig_map, bt=begin_time, et=end_time,
              format=waveform.VctFormat_e.HexStrVal)
while me.iter_next():
    pass  # process message
me.iter_stop()
```

## Enums

| Enum | Values |
|------|--------|
| `RelationDirType_e` | Master(0), Slave(1) |
| `CallStackType_e` | Begin(0), End(1) |
| `TrtType_e` | Message(0), Transaction(1), Action(2), Group(3) |
| `Protocol_e` | APB(0), AHB(1), AXI(2) |
| `ValFormat_e` | Same as VctFormat_e: BinStrVal(0)..ObjTypeVal(11) |

## Common Patterns

### AXI Transaction Analysis
```python
stream = f.stream_by_name("$trans_root.axi_wr")
f.add_to_stream_list(stream)
f.load_trans()
trt = stream.create_trt()
if trt.goto_first():
    while True:
        begin, end = trt.time()
        for i in range(trt.attr_count()):
            name = trt.attr_name(i)
            val = trt.attr_value(i, waveform.ValFormat_e.HexStrVal)
            if "addr" in name.lower():
                print(f"Write @ t={begin}: addr={val}")
        if not trt.goto_next():
            break
    trt.release()
f.unload_trans()
```

### Correlate with Signal Waveform
```python
# Read signal values at transaction boundaries
begin, end = trt.time()
val = waveform.sig_value_at(f, "top.bus.data", begin, waveform.VctFormat_e.HexStrVal)
```

### Protocol Violation Detection
```python
prev_end = 0
trt.goto_first()
while True:
    begin, end = trt.time()
    if begin < prev_end:
        print(f"OVERLAP: trt {trt.id()} starts {begin} < prev_end {prev_end}")
    prev_end = end
    if not trt.goto_next():
        break
```

## Pitfalls

- **MUST call `load_trans()` before accessing transactions** — forgetting causes None returns
- **MUST call `unload_trans()` and `trt.release()` when done**
- Transaction time is `[begin, end]` list, not a single int
- `goto_time(t)` finds transaction active at time t, not starting at t
- Streams must be added via `add_to_stream_list()` before `load_trans()`
