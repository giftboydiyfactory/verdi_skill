---
name: verdi-netlist
version: 0.1.0
description: "This skill should be used when the user asks to 'trace driver', 'find load', 'get port map', 'check connectivity', 'fan-in analysis', or needs to traverse design netlist via KDB. Provides the pynpi.netlist API reference."
---

# pynpi.netlist API Reference

## Quick Start

```python
from pynpi import npisys, netlist
npisys.init(sys.argv)
npisys.load_design(sys.argv)  # Need design files for netlist
inst = netlist.get_inst("top.cpu")
for net in inst.net_list():
    drivers = net.driver_list()
    print(f"{net.full_name()}: {len(drivers)} drivers")
npisys.end()
```

Note: netlist requires `npisys.load_design()` with RTL source files, unlike waveform which only needs FSDB.

## Enums

### ObjectType
Identifies the type of a netlist object.

| Value | Description |
|-------|-------------|
| `ObjectType.INST` | Design instance |
| `ObjectType.PORT` | Module port |
| `ObjectType.INSTPORT` | Instance port (pin on a child instance) |
| `ObjectType.DECL_NET` | Declared net |
| `ObjectType.CONCAT_NET` | Concatenated net |
| `ObjectType.SLICE_NET` | Bit-sliced net |
| `ObjectType.PSEUDO_PORT` | Pseudo port |
| `ObjectType.PSEUDO_INSTPORT` | Pseudo instance port |
| `ObjectType.PSEUDO_NET` | Pseudo net |
| `ObjectType.LIB` | Library |
| `ObjectType.CELL` | Library cell |
| `ObjectType.CELLPIN` | Library cell pin |

### FuncType
Specifies the analysis function type for connectivity queries.

| Value | Description |
|-------|-------------|
| `FuncType.SIG_TO_SIG` | Signal-to-signal connection tracing |
| `FuncType.FAN_IN` | Fan-in analysis (trace backwards to sources) |
| `FuncType.FAN_OUT` | Fan-out analysis (trace forwards to loads) |

### ValueFormat
Format for retrieving net values.

| Value | Description |
|-------|-------------|
| `ValueFormat.BIN` | Binary |
| `ValueFormat.OCT` | Octal |
| `ValueFormat.HEX` | Hexadecimal |
| `ValueFormat.DEC` | Decimal |

## Handle Retrieval

Top-level functions to obtain netlist handles by hierarchical name.

| Function | Returns | Description |
|----------|---------|-------------|
| `netlist.get_inst(name)` | `InstHdl` | Get instance handle by hierarchical name |
| `netlist.get_port(name)` | `PinHdl` | Get module port handle |
| `netlist.get_instport(name)` | `PinHdl` | Get instance port handle |
| `netlist.get_net(name)` | `NetHdl` | Get net handle |
| `netlist.get_top_inst_list()` | `[InstHdl]` | Get all top-level instances |
| `netlist.get_actual_net(name)` | `NetHdl` | Get actual (resolved) net handle |

```python
# Examples
top = netlist.get_inst("top")
clk_port = netlist.get_port("top.clk")
sub_pin = netlist.get_instport("top.cpu.data_in")
sig = netlist.get_net("top.cpu.internal_bus")
tops = netlist.get_top_inst_list()
```

## InstHdl (Instance)

Represents a design instance (module instantiation) in the hierarchy.

### Properties

| Method | Returns | Description |
|--------|---------|-------------|
| `name()` | `str` | Instance name (local) |
| `full_name()` | `str` | Full hierarchical name |
| `def_name()` | `str` | Definition (module) name |
| `lang_type()` | `str` | HDL language type (Verilog, VHDL, etc.) |
| `cell_type()` | `str` | Cell type classification |
| `inst_type()` | `str` | Instance type |
| `src_info()` | `str` | Source file information |
| `file()` | `str` | Source file path |
| `begin_line_no()` | `int` | Starting line number in source |
| `end_line_no()` | `int` | Ending line number in source |
| `is_interface()` | `bool` | True if this is an interface instance |
| `is_memory_cell()` | `bool` | True if this is a memory cell |
| `is_pad_cell()` | `bool` | True if this is a pad cell |

### Children and Connectivity

| Method | Returns | Description |
|--------|---------|-------------|
| `inst_list()` | `[InstHdl]` | Child instances |
| `net_list()` | `[NetHdl]` | Internal nets within this scope |
| `port_list()` | `[PinHdl]` | Module ports |
| `instport_list()` | `[PinHdl]` | Instance ports (pins on child instances) |
| `driver_instport_list()` | `[PinHdl]` | Instance ports that are drivers |
| `load_instport_list()` | `[PinHdl]` | Instance ports that are loads |
| `scope_inst()` | `InstHdl` | Parent scope instance |

```python
inst = netlist.get_inst("top.cpu")
print(f"Module: {inst.def_name()}, File: {inst.file()}:{inst.begin_line_no()}")

# Walk child instances
for child in inst.inst_list():
    print(f"  Child: {child.name()} ({child.def_name()})")

# List all ports
for port in inst.port_list():
    print(f"  Port: {port.name()} dir={port.direction()}")

# Get parent
parent = inst.scope_inst()
```

## PinHdl (Port / InstPort)

Represents a port on a module or a pin on an instance.

### Properties

| Method | Returns | Description |
|--------|---------|-------------|
| `name()` | `str` | Pin name (local) |
| `full_name()` | `str` | Full hierarchical name |
| `direction()` | `str` | Direction: input, output, inout |
| `size()` | `int` | Bit width |
| `left()` | `int` | Left index of bit range |
| `right()` | `int` | Right index of bit range |
| `port_type()` | `str` | Port type classification |

### Connectivity

| Method | Returns | Description |
|--------|---------|-------------|
| `connected_pin()` | `PinHdl` | Connected pin (across hierarchy boundary) |
| `connected_net()` | `NetHdl` | Net connected to this pin |
| `driver_list()` | `[PinHdl]` | Pins driving this pin |
| `load_list()` | `[PinHdl]` | Pins loaded by this pin |
| `scope_inst()` | `InstHdl` | Instance this pin belongs to |

```python
port = netlist.get_port("top.cpu.data_out")
print(f"{port.full_name()} [{port.left()}:{port.right()}] {port.direction()}")

# Trace what drives this port
for drv in port.driver_list():
    print(f"  Driven by: {drv.full_name()}")

# Get the net on the other side
net = port.connected_net()
```

## NetHdl (Net) -- KEY for Driver/Load Tracing

Represents a net (wire/signal) in the design. This is the primary handle for connectivity analysis.

### Properties

| Method | Returns | Description |
|--------|---------|-------------|
| `name()` | `str` | Net name (local) |
| `full_name()` | `str` | Full hierarchical name |
| `net_type()` | `str` | Net type (wire, reg, logic, etc.) |
| `size()` | `int` | Bit width |
| `left()` | `int` | Left index of bit range |
| `right()` | `int` | Right index of bit range |
| `value(format)` | `str` | Current value in specified format |

### Driver/Load Tracing

| Method | Returns | Description |
|--------|---------|-------------|
| `driver_list()` | `[PinHdl]` | All drivers of this net |
| `load_list()` | `[PinHdl]` | All loads on this net |
| `fan_in_reg_list()` | list | Register fan-in chain (trace back to source registers) |
| `fan_out_reg_list()` | list | Register fan-out chain (trace forward to destination registers) |
| `to_sig_conn_list(to_hdl, assign_cell=False)` | list | Signal-to-signal connection path to target |

```python
# Basic driver/load analysis
net = netlist.get_net("top.cpu.alu_result")
print(f"{net.full_name()} [{net.left()}:{net.right()}] type={net.net_type()}")

# Who drives this net?
for driver in net.driver_list():
    print(f"  Driver: {driver.full_name()} ({driver.direction()})")

# Who consumes this net?
for load in net.load_list():
    print(f"  Load: {load.full_name()} ({load.direction()})")

# Register chain analysis
fan_in_regs = net.fan_in_reg_list()
print(f"Fan-in registers: {len(fan_in_regs)}")

fan_out_regs = net.fan_out_reg_list()
print(f"Fan-out registers: {len(fan_out_regs)}")

# Signal-to-signal path
target = netlist.get_net("top.cpu.write_data")
connections = net.to_sig_conn_list(target, assign_cell=False)
```

## LibHdl / CellHdl / CellPinHdl

Library, cell, and cell pin handles for technology library queries.

| Function / Method | Returns | Description |
|-------------------|---------|-------------|
| `netlist.get_top_lib_list()` | `[LibHdl]` | All top-level libraries |
| `lib.cell_list()` | `[CellHdl]` | Cells in a library |
| `cell.cellpin_list()` | `[CellPinHdl]` | Pins on a library cell |

```python
for lib in netlist.get_top_lib_list():
    for cell in lib.cell_list():
        pins = cell.cellpin_list()
        print(f"  {cell.name()}: {len(pins)} pins")
```

## Hierarchy Traversal

Callback-driven traversal of the design hierarchy tree.

| Function | Description |
|----------|-------------|
| `netlist.hier_tree_trv(scope_hier_name=None)` | Execute traversal (optionally scoped to a subtree) |
| `netlist.hier_tree_trv_register_cb(obj_type, cb_func, cb_data)` | Register callback for a given object type |
| `netlist.hier_tree_trv_reset_cb()` | Clear all registered callbacks |
| `netlist.sig_to_sig_conn_list(from_hdl, to_hdl, assign_cell=False)` | Trace signal-to-signal connections between two handles |

```python
# Register callbacks then traverse
def on_inst(inst, data):
    data["count"] += 1
    print(f"Visited: {inst.full_name()}")

data = {"count": 0}
netlist.hier_tree_trv_reset_cb()
netlist.hier_tree_trv_register_cb(ObjectType.INST, on_inst, data)
netlist.hier_tree_trv(scope_hier_name="top.cpu")
print(f"Total instances visited: {data['count']}")

# Cross-hierarchy signal-to-signal trace
src = netlist.get_net("top.cpu.req")
dst = netlist.get_net("top.mem_ctrl.req_in")
path = netlist.sig_to_sig_conn_list(src, dst, assign_cell=False)
for step in path:
    print(f"  -> {step.full_name()}")
```

## Common Patterns

### Driver Trace
```python
net = netlist.get_net("top.sig")
drivers = net.driver_list()
for d in drivers:
    print(f"Driver: {d.full_name()}")
```

### Load Fan-Out
```python
net = netlist.get_net("top.sig")
loads = net.load_list()
for l in loads:
    print(f"Load: {l.full_name()}")
```

### Register-to-Register Path Analysis
```python
net = netlist.get_net("top.cpu.pipeline_data")
# Trace backwards to source registers
fan_in = net.fan_in_reg_list()
# Trace forwards to destination registers
fan_out = net.fan_out_reg_list()
```

### Cross-Hierarchy Signal Connection
```python
src = netlist.get_net("top.producer.out_data")
dst = netlist.get_net("top.consumer.in_data")
path = netlist.sig_to_sig_conn_list(src, dst, assign_cell=False)
```

### Full Hierarchy Walk
```python
def walk_hierarchy(inst, depth=0):
    indent = "  " * depth
    print(f"{indent}{inst.name()} ({inst.def_name()})")
    for child in inst.inst_list():
        walk_hierarchy(child, depth + 1)

for top in netlist.get_top_inst_list():
    walk_hierarchy(top)
```

### Find All Drivers of a Port Recursively
```python
def trace_to_source(pin, visited=None):
    if visited is None:
        visited = set()
    name = pin.full_name()
    if name in visited:
        return []
    visited.add(name)
    sources = []
    net = pin.connected_net()
    if net is None:
        return [pin]
    for drv in net.driver_list():
        sources.extend(trace_to_source(drv, visited))
    return sources if sources else [pin]
```
