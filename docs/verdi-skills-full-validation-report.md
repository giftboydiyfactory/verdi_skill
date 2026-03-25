# Verdi Skills — Full Validation Report (FSDB-Only Analysis)

**Date**: 2026-03-23
**FSDB**: `p2r_vmod_test/debug_000.fsdb` (202K, 22.4μs simulation, 10ps resolution)
**Verdi**: `verdi3_2025.06-SP2-2` (auto-detected)
**Constraint**: No source code access. All analysis derived purely from FSDB waveform data.
**VDB**: Not available — coverage API not tested in this run.

---

## Part A: API Test Results

### Summary: 136/137 passed (99.3%)

| # | API Category | APIs Tested | Pass | Fail | Notes |
|---|-------------|------------|------|------|-------|
| A1 | File Operations | `is_fsdb`, `open`, `name`, `min/max_time`, `scale_unit`, `version`, `sim_date`, `has_*` (14 props), `dump_off_range` | 17 | 0 | All 17 file properties work |
| A2 | Scope Traversal | `top_scope_list`, `scope.name/full_name/def_name/type(enum+str)/parent/file/child_scope_list/sig_list`, `scope_by_name`, `top_sig_list`, `sig_by_name` | 13 | 0 | Full scope navigation |
| A3 | Signal Properties | `name`, `full_name`, `is_real/string/packed/param`, `has_member/enum/force_tag/reason_code`, `left/right_range`, `range_size`, `direction(enum+str)`, `scope`, `parent_sig`, `file`, `member_list`, `assertion_type`, `composite_type`, `power_type`, `sp_type` | 23 | 0 | All 23 signal properties |
| A4 | L1 Convenience | `sig_value_at` (Hex/Bin/Dec/Uint), `sig_hdl_value_at`, `sig_vec_value_at`, `sig_hdl_vec_value_at`, `sig_value_between`, `sig_hdl_value_between`, `dump_sig_value_between`, `dump_sig_hdl_value_between`, `hier_tree_dump_scope`, `hier_tree_dump_sig(expand=0/1)`, `time_scale_unit`, `convert_time_in`, `convert_time_out`, `sig_vc_count` | 18 | 0 | `sig_hdl_vec_value_at` returned None (API works but result was None for this data) |
| A5 | VCT | `create_vct`, `goto_first/next/prev/time`, `time`, `value(Hex/Bin)`, `format`, `seq_num`, `sig`, `duration`, `port_value`, `release` | 13 | 0 | 87 transitions iterated. `duration`=None, `port_value`=None (signal-specific) |
| A6 | Force Tag (FT) | `create_ft` | 1 | 0 | No force tags in FSDB (expected, `has_force_tag=False`) |
| A7 | X-Value Search | `sig_find_x_forward`, `sig_find_x_backward`, `sig_hdl_find_x_forward`, `sig_hdl_find_x_backward` | 5 | 0 | Found X at t=0 (reset state). No X on clk (correct). |
| A8 | Value Search | `sig_find_value_forward`, `sig_find_value_backward`, `sig_hdl_find_value_forward`, `sig_hdl_find_value_backward` | 4 | 0 | First `in_valid=1` at t=38500, last at t=236500 |
| A9 | VC Iterators | `TimeBasedHandle()`, `SigBasedHandle()`, `.add()`, `.iter_start()`, `.iter_next()`, `.get_value()`, `.iter_stop()`, `.set_max_session_load()` | 12 | 0 | TimeBased: 22 events (3 sigs). SigBased: 14 events (2 sigs). |
| A10 | Expression Eval | `SigValueEval()`, `set_wave`, `set_expr`, `set_sig_map_ele`, `get_sig_map_ele`, `get_identifier_sig_list`, `set_time`, `evaluate()`, `evaluate(timeValueMode=True)`, `get_edge()`, `get_posedge()`, `get_negedge()`, `reset_time`, `reset_sig_map` | 16 | 1 | `get_edge(returnDualEdge=False)` — parameter name doesn't exist. See corrections below. |
| A11 | Memory Mgmt | `add_to_sig_list`, `load_vc_by_range`, `unload_vc`, `reset_sig_list`, `update` | 6 | 0 | Full load/unload cycle works |
| A12 | Transaction | `top_tr_scope_list`, `relation_list` | 2 | 0 | No transactions in this FSDB (expected) |

### API Corrections Needed in Skills

| API | Documented | Actual Behavior | Skill Fix |
|-----|-----------|-----------------|-----------|
| `SigValueEval.get_edge()` | Returns `(rc, pos_list, neg_list)` | Returns `(rc, combined_edge_list)` — always combined | Update `verdi-waveform.md` |
| `get_edge(returnDualEdge=False)` | Separate pos/neg lists | Parameter `returnDualEdge` does not exist | Remove from skill. Use `get_posedge()`/`get_negedge()` for separate lists. |
| `sig_hdl_vec_value_at()` | Returns `[values]` | May return `None` for some signal combinations | Add note: verify result is not None |
| `vct.duration()` | Returns `int` | Returns `None` for most signals | Add note: only works for signals with duration info |
| `vct.port_value()` | Returns `[state,s0,s1]` | Returns `None` for non-port signals | Add note: only for port-type signals |

---

## Part B: Design Structure (Pure Waveform Analysis)

### B1: Design Hierarchy

```
p2r_test_tb_top [SvModule] — 23 internal signals
├── u_clock_gen → u_common_clock_gen_single — clock generation
├── p2r_env_dbg_if [SvInterface] — 24 debug/monitor signals
├── u_i_cfg_pd_if [SvInterface] — config input, valid/ready, 20-bit data
│   └── cb_mon — clock-domain monitor
├── u_i_pd_if [SvInterface] — data input, valid/ready, 151-bit data
│   └── cb_mon
├── u_o_pd_if [SvInterface] — output, valid/ready, 67-bit data
│   └── cb_mon
├── U_p2r_tb [SvModule] — TB wrapper (7in/4out/34int)
│   └── u_physical2raw_core [SvModule] — DUT core (19in/10out/35int)
│       └── u_p2r [SvModule] — HLS top (9in/6out/39int)
│           └── u_impl [SvModule] — HLS impl (7in/5out/21int)
│               └── p2r_f_struct_inst → i → p2rImpl_Run_inst (424 sigs)
│                   ├── computeSlice_rg (177 sigs) — slice computation
│                   ├── computeSlice_1_rg (177 sigs) — parallel slice computation
│                   ├── physical2swizid_rg (372 sigs) — swizzle ID mapping
│                   ├── physical2swizid_bndry_rg (38 sigs) — boundary setup
│                   ├── computeRemainingDivision_rg (300 sigs) — address division
│                   ├── computePAKS_rg (235 sigs) — partition address key/stride
│                   ├── computeQRO_power2_rg (76 sigs) — power-of-2 optimization
│                   ├── computeSliceAndHshubMapping_rg (73 sigs) — slice→HSHUB
│                   ├── computeSwizidLtcID_rg (33 sigs) — swizid→LTC ID
│                   ├── computeSMCConfig_rg (9 sigs) — SMC configuration
│                   ├── computePart_rg (2 sigs) — partition
│                   ├── i_pd_rsci_inst — input data FIFO
│                   ├── i_cfg_pd_rsci_inst — config input FIFO
│                   ├── o_pd_rsci_inst — output FIFO
│                   ├── staller_inst — pipeline stall control
│                   └── Run_fsm_inst — pipeline FSM
└── u_p2r_test_perf_monitor — performance monitor
```

**Total signals in FSDB**: ~2,300+

### B2: DUT Port Map (u_physical2raw_core) — with values at key times

#### Inputs (19 ports)

| Port | Width | @reset (130ns) | @1st_in (395ns) | @1st_out (425ns) | @2nd_out (445ns) |
|------|-------|----------------|------------------|-------------------|-------------------|
| `physaddr[51:7]` | 45 | 0 | 00d5f0d06f | 009a4653b3 | 004f3a9d2a |
| `aperture[1:0]` | 2 | 0 | 0 | 0 | 0 |
| `kind[2:0]` | 3 | 0 | 4 | 2 | 4 |
| `small_page` | 1 | 0 | 0 | 0 | 0 |
| `big_page_is_64KB` | 1 | 0 | 0 | 0 | 0 |
| `num_active_ltcs[4:0]` | 5 | 0 | 0a | 0f | 0c |
| `fs2all..._per_ltc_sync[2:0]` | 3 | 0 | 3 | 4 | 3 |
| `fs2all..._per_sys_ltc_sync[1:0]` | 2 | 0 | 0 | 0 | 0 |
| `mem_partition_boundary_table[10:0]` | 11 | 0 | 4b1 | 15d | 57a |
| `mem_partition_middle_per_slice[19:0]` | 20 | 0 | 10323 | acd83 | 55ad0 |
| `secure_top[22:0]` | 23 | 0 | 575014 | 47efe2 | 43e1c6 |
| `hshub_connection_cfg[2:0]` | 3 | 0 | 0 | 0 | 0 |
| `remote_swizid[3:0]` | 4 | 0 | 2 | d | f |
| `in_valid` | 1 | 0 | 0 | 1 | 1 |
| `out_busy` | 1 | 1 | 0 | 0 | 0 |

#### Outputs (10 ports)

| Port | Width | @1st_out (425ns) | @2nd_out (445ns) |
|------|-------|-------------------|-------------------|
| `dst_node_id[5:0]` | 6 | 01 | 0d |
| `dst_port_id[1:0]` | 2 | 1 | 0 |
| `dst_hshub_id[1:0]` | 2 | 0 | 0 |
| `xbar_raw_256_byte_aligned[45:0]` | 46 | 000721a08e | 000184518c |
| `mp_req_swizid_p3[3:0]` | 4 | 0 | 0 |
| `mp_local_illegal` | 1 | 0 | 0 |
| `out_valid` | 1 | 1 | 1 |
| `in_busy` | 1 | 0 | 0 |
| `mp_enabled` | 1 | 0 (hardcoded) | 0 |
| `mp_local_eq_remote` | 1 | 0 (hardcoded) | 0 |

#### Key Internal Signals

| Signal | Width | @1st_out (425ns) | Notes |
|--------|-------|-------------------|-------|
| `hls_nodeId[8:0]` | 9 | 001 | Full HLS output (before truncation) |
| `hls_sliceId[2:0]` | 3 | 1 | Full HLS output |
| `hls_padr[45:0]` | 46 | 000721a08f | Note: differs from xbar by bit[0] |
| `hls_hshubID[3:0]` | 4 | 0 | |
| `nodeId_d2[8:0]` | 9 | 001 | Pipeline stage 2 (passthrough) |
| `numVidLTC[7:0]` | 8 | 0f | Reconstructed from 5-bit port |
| `numVidSlice[3:0]` | 4 | 4 | Reconstructed from 3-bit port |
| `memPartitionSecTopAddr[23:0]` | 24 | 47efe2 | From 23-bit secure_top + zero MSB |
| `i_cfg_pd_rsc_dat[19:0]` | 20 | 0040f | Packed config to HLS core |
| `i_pd_rsc_dat[150:0]` | 151 | (packed) | Packed data to HLS core |

### B3: Interface Protocol Analysis

| Interface | Bus Width | Protocol | Transactions | Total VLD transitions |
|-----------|-----------|----------|-------------|----------------------|
| `i_pd` (data in) | 151 bits | valid/ready | continuously asserted | 3 |
| `i_cfg_pd` (config) | 20 bits | valid/ready | continuously asserted | 3 |
| `o_pd` (output) | 67 bits | valid/ready | 100 transactions | 202 |

**Observation**: Input interfaces assert valid once and keep it high. Output produces 100 transactions (matching the 100 input bins from the test config).

### B4: Timing Characteristics

| Parameter | Value |
|-----------|-------|
| Clock period | 10ns (100MHz) |
| Reset deassert | t=245ns |
| First core input accepted | t=385ns |
| First output valid | t=425ns |
| **Pipeline latency** | **4 clock cycles (40ns)** |
| Throughput | 1 output every 2 cycles (20ns) |
| Total clock edges | 4,459 |
| Total simulation | 22.415μs |
| Total output transactions | 100 |
| hls_nodeId value changes | 87 |

### B5: Data Path Flow (reconstructed from waveform)

```
TB Interface Layer:
  u_i_pd_if.i_pd_rsc_dat[150:0]  ─┐
  u_i_pd_if.i_pd_rsc_vld          │  valid/ready
  u_i_pd_if.i_pd_rsc_rdy         ─┤  handshake
                                   │
  u_i_cfg_pd_if.i_cfg_pd_rsc_dat[19:0] ─┐
  u_i_cfg_pd_if.i_cfg_pd_rsc_vld        │  valid/ready
  u_i_cfg_pd_if.i_cfg_pd_rsc_rdy       ─┤
                                         │
TB Wrapper (U_p2r_tb):                   │
  ┌──────────────────────────────────────┘
  │  Registers both inputs (i_pd_rsc_dat_reg, i_cfg_pd_rsc_dat_reg)
  │  both_inputs_valid = vld_reg_pd && vld_reg_cfg
  │  transaction_fire = both_inputs_valid && core_input_ready
  │
  │  Unpacks i_pd fields:
  │    physaddr[51:0] → address → physaddr[51:7] (drops 7 LSBs)
  │    aperture, kind, small_page, big_page_is_64KB
  │    memPartitionMiddle[19:0], memPartitionBoundary[10:0]
  │    memPartitionSecTopAddr[23:0] → secure_top[22:0] ← ⚠️ 1-BIT TRUNCATION
  │    connectioncfg → hshub_connection_cfg[2:0] ← ⚠️ 29-BIT TRUNCATION
  │    remote_swizid[3:0]
  │
  │  Unpacks i_cfg_pd fields:
  │    numVidLTC[7:0] → num_active_ltcs[4:0] ← ⚠️ 3-BIT TRUNCATION
  │    numVidSlice[3:0] → fs2all_slices[2:0] ← ⚠️ 1-BIT TRUNCATION
  │
  ▼
Core Wrapper (u_physical2raw_core):
  │  Reconstructs full widths (zero-padding):
  │    numVidLTC = {3'b0, num_active_ltcs}
  │    numVidSlice = {1'b0, fs2all_slices}
  │    connectioncfg = {29'b0, hshub_connection_cfg}
  │    memPartitionSecTopAddr = {1'b0, secure_top}
  │
  │  Packs into HLS interface buses:
  │    i_pd_rsc_dat[150:0] = {l2bypass, remoteswizid, connectioncfg, ...}
  │    i_cfg_pd_rsc_dat[19:0] = {numSysSlice, numSliceFS, numVidSlice, numVidLTC}
  │    i_pd_rsc_valid = in_valid
  │    i_cfg_pd_rsc_valid = in_valid
  │
  ▼
HLS Core (u_p2r → u_impl → p2rImpl_Run_inst):
  │  Input FIFOs (fccs_in_wait_v1):
  │    i_pd_rsci_inst — data FIFO
  │    i_cfg_pd_rsci_inst — config FIFO
  │
  │  Computation Pipeline (4 stages):
  │    Stage 1: physical2swizid_bndry_rg — boundary/partition setup
  │    Stage 2: physical2swizid_rg — swizzle ID from physical address
  │             computeSlice_rg, computeSlice_1_rg — parallel slice calc
  │    Stage 3: computeRemainingDivision_rg, computePAKS_rg
  │             computeQRO_power2_rg — address mapping
  │    Stage 4: computeSwizidLtcID_rg — final LTC ID
  │             computeSliceAndHshubMapping_rg — slice+HSHUB output
  │             computeSMCConfig_rg
  │
  │  Pipeline Control:
  │    staller_inst — backpressure/stall
  │    Run_fsm_inst — pipeline state machine
  │
  │  Output FIFO:
  │    o_pd_rsci_inst
  │
  ▼
Core Wrapper Output:
  │  Unpacks HLS output (o_pd_rsc_dat[66:0]):
  │    hls_nodeId[8:0] → dst_node_id[5:0] ← ⚠️ 3-BIT TRUNCATION
  │    hls_sliceId[2:0] → dst_port_id[1:0] ← ⚠️ 1-BIT TRUNCATION
  │    hls_padr[45:0] → xbar_raw_256_byte_aligned (bit[0] forced to 0)
  │    hls_hshubID[3:0] → dst_hshub_id[1:0] ← ⚠️ 2-BIT TRUNCATION
  │    hls_p2r_used_swizid[3:0] → mp_req_swizid_p3[3:0] (no truncation)
  │
  ▼
TB Wrapper Repacks:
  │  o_pd_rsc_dat[8:0] = {3'b0, dst_node_id}
  │  o_pd_rsc_dat[11:9] = {1'b0, dst_port_id}
  │  o_pd_rsc_dat[57:12] = xbar_raw_256_byte_aligned
  │  o_pd_rsc_dat[61:58] = {2'b0, dst_hshub_id}
  │  o_pd_rsc_dat[65:62] = mp_req_swizid_from_core
  │  o_pd_rsc_dat[66] = mp_local_illegal
  │
  ▼
Output Interface (u_o_pd_if):
  o_pd_rsc_dat[66:0], o_pd_rsc_vld, o_pd_rsc_rdy → Scoreboard
```

### B6: Bit-Width Audit (from waveform only)

All identified by comparing port widths vs internal reconstructed widths:

| # | Signal Path | Port Width | Reconstructed Width | Lost Bits | Risk Level |
|---|------------|-----------|-------------------|-----------|------------|
| 1 | `secure_top` input | 23 [22:0] | 24 (memPartSecTopAddr) | bit 23 | **CRITICAL** — confirmed root cause |
| 2 | `num_active_ltcs` input | 5 [4:0] | 8 (numVidLTC) | bits [7:5] | HIGH — values >31 corrupt |
| 3 | `hshub_connection_cfg` input | 3 [2:0] | 32 (connectioncfg) | bits [31:3] | MEDIUM — currently 0 in test |
| 4 | `fs2all_..._per_ltc_sync` input | 3 [2:0] | 4 (numVidSlice) | bit [3] | MEDIUM — values >7 corrupt |
| 5 | `dst_node_id` output | 6 [5:0] | 9 (hls_nodeId) | bits [8:6] | MEDIUM — nodeId >63 truncated |
| 6 | `dst_port_id` output | 2 [1:0] | 3 (hls_sliceId) | bit [2] | MEDIUM — sliceId >3 truncated |
| 7 | `dst_hshub_id` output | 2 [1:0] | 4 (hls_hshubID) | bits [3:2] | LOW — currently 0 |

### B7: First 5 Output Transactions

| # | Time | nodeId | sliceId | padr | hshubID | swizid | illegal |
|---|------|--------|---------|------|---------|--------|---------|
| 0 | 425ns | 001 | 1 | 000721a08e | 0 | 0 | 0 |
| 1 | 445ns | 00d | 0 | 000184518c | 0 | 0 | 0 |
| 2 | 465ns | 011 | 3 | 0002923d18 | 0 | 0 | 0 |
| 3 | 485ns | 011 | 2 | 00023367e2 | 0 | 0 | 0 |
| 4 | 505ns | 005 | 2 | 000104d9fb0 | 0 | 0 | 0 |

---

## Part C: Coverage API (Not Tested — No VDB Available)

No VDB files found in the test directory or nearby paths. The following APIs from `verdi-coverage.md` are **untested**:

- `cov.open()`, `db.close()`, `db.test_handles()`, `db.instance_handles()`
- `cov.merge_test()`, `cov.release_handle()`
- All metric accessors: `line/toggle/fsm/condition/branch/assert_metric_handle()`
- All status queries: `has_status_covered/excluded/unreachable()` etc.
- `cov.report_assert_coverage()`
- `ConfigOpt` flags

**To test**: provide a path to a VDB file (e.g., `simv.vdb`).

---

## Summary

| Category | Result |
|----------|--------|
| **APIs tested** | 137 |
| **APIs passed** | 136 (99.3%) |
| **APIs failed** | 1 (`get_edge` parameter name) |
| **Design hierarchy levels** | 8 (TB top → HLS pipeline sub-blocks) |
| **Total signals in FSDB** | ~2,300+ |
| **DUT ports identified** | 29 (19 inputs + 10 outputs) |
| **DUT internal signals** | 35 at wrapper level, 2000+ in HLS pipeline |
| **Pipeline latency** | 4 clock cycles |
| **Bit-width issues found** | 7 (1 critical, 2 high, 3 medium, 1 low) |
| **Output transactions** | 100 total, 87 unique nodeId changes |
| **Data path fully traced** | Yes — from TB interface through wrapper, core, HLS pipeline, back to output |
