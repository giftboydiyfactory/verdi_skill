## 12. Full-Stack Debug Methodology (FSDB + KDB + VDB)

This section describes the complete debug methodology using ALL available data sources — not just waveforms. The key principle: **extract everything from the database, never rely on reading source code manually**.

### Data Sources and What They Provide

| Source | API | What It Provides | When to Use |
|--------|-----|-------------|-------------|
| **FSDB** | `pynpi.waveform` | Signal values over time, transitions, X-values | Always — primary debug data |
| **KDB** (simv.daidir) | `pynpi.lang`, `pynpi.netlist` | RTL structure, signal tracing, source file/line, connectivity | When tracing drivers/loads or understand design structure |
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

**Critical**: Compare ALL signals systematically, not just the suspected ones. The root cause is often in an unexpected signal.

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
   - Compare ALL simTop signals (not just the expected ones)
   - Categorize: which are truly seed-dependent vs which are build-dependent?
   - TB randomization params identical? → problem is in address mapping
   - TB randomization params different? → problem is in stimulus generation

### Key Principles

1. **Database first, source code never** — Use `pynpi.lang` to get source file:line instead of reading .v/.sv files directly. The KDB has the elaborated, resolved view.

2. **Systematic over targeted** — Compare ALL signals, not just suspects. The root cause is often in an unexpected place (e.g., SLCG delay causing X in output register).

3. **Normalize before comparing** — Different seeds/tests have different simulation times. Always normalize throughput by window length.

4. **Trace the full chain** — From symptom (X on output) → through pipeline (clock-gated register) → to root cause (SLCG timing mismatch). Use `sig_find_x_forward/backward` + `lang.trace_driver2` together.

5. **Cross-reference sources** — FSDB shows WHAT happened (values, timing). KDB shows WHERE in the code (file:line, connectivity). VDB shows WHAT'S UNTESTED (coverage gaps). Use all three together.
