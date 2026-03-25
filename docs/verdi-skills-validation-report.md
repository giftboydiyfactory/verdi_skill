# Verdi Skills Plugin — Validation Report

**Date**: 2026-03-23
**FSDB**: `/home/scratch.yizhong_mobile_2/.../p2r_vmod_test/debug_000.fsdb` (202K, 22.4us, 10ps scale)
**Verdi**: `verdi3_2025.06-SP2-2` (auto-detected)

---

## 1. API Test Results

**49 / 50 passed (98%)**

| Section | APIs Tested | Pass | Fail | Notes |
|---------|------------|------|------|-------|
| File Operations | `open`, `close`, `is_fsdb`, 14 properties | 16 | 0 | All file metadata accessible |
| Scope Traversal | `top_scope_list`, `scope_by_name`, `child_scope_list`, `sig_list`, scope properties | 10 | 0 | Full hierarchy traversable |
| Signal Properties | `name`, `full_name`, `direction`, `range`, `is_real`, `is_packed`, `has_member`, `scope`, etc. | 17 | 0 | All 17 property methods work |
| L1 Convenience | `sig_value_at` (4 formats), `sig_hdl_value_at`, `sig_vec_value_at`, `sig_value_between`, `sig_hdl_value_between`, `dump_sig_value_between`, `time_scale_unit`, `convert_time_in/out`, `hier_tree_dump_scope/sig`, `sig_vc_count` | 14 | 0 | Core APIs all working |
| VCT | `create_vct`, `goto_first/next/prev/time`, `time`, `value`, `format`, `sig`, `release` | 10 | 0 | Full VCT lifecycle tested |
| X-Value Search | `sig_find_x_forward`, `sig_find_x_backward` | 3 | 0 | Found X at reset (t=0), None when no X in range |
| Value Search | `sig_find_value_forward`, `sig_find_value_backward` | 2 | 0 | Forward: first `in_valid=1` at t=38500; Backward: last at t=236500 |
| VC Iterators | `TimeBasedHandle`, `SigBasedHandle` — `add`, `iter_start/next/stop`, `get_value` | 6 | 0 | TimeBased: 22 events for 2 sigs; SigBased: 8 events |
| Expression Eval | `SigValueEval` — `set_wave/expr/sig_map_ele/time`, `evaluate`, `get_edge` | 4 | 1 | `evaluate()` works (9 true, 10 false times). `get_edge()` returns tuple of 2 not 3 — skill needs update |
| Memory Mgmt | `add_to_sig_list`, `load_vc_by_range`, `unload_vc`, `reset_sig_list` | 4 | 0 | Load/unload cycle works correctly |
| Transaction | `top_tr_scope_list` | 1 | 0 | No transactions in this FSDB (expected) |

### API Issue Found

**`SigValueEval.get_edge()`** returns `(rc, edge_list)` (2 values), not `(rc, posedge_list, negedge_list)` (3 values) as documented. The skill should be updated to note that `get_edge(returnDualEdge=True)` returns combined edges.

---

## 2. Design Structure (Reverse-Engineered from Waveform)

### Hierarchy

```
p2r_test_tb_top (SvModule) — 23 signals
├── u_clock_gen (SvModule) — clock generation
│   └── generate_clk[0] → u_common_clock_gen_single
├── p2r_env_dbg_if (SvInterface) — 24 debug/monitor signals
├── u_i_cfg_pd_if (SvInterface) — 10 sigs, config input interface
│   └── cb_mon — clock block monitor
├── u_i_pd_if (SvInterface) — 17 sigs, data input interface
│   └── cb_mon — clock block monitor
├── u_o_pd_if (SvInterface) — 12 sigs, output interface
│   └── cb_mon — clock block monitor
├── U_p2r_tb (SvModule) — 45 sigs, TB wrapper
│   └── u_physical2raw_core (SvModule) — 64 sigs, DUT core wrapper
│       └── u_p2r (SvModule) — 54 sigs, HLS top
│           └── u_impl (SvModule) — 33 sigs, HLS impl
│               └── p2r_f_struct_inst → i → p2rImpl_Run_inst (424 sigs)
│                   ├── computeSlice_rg (177 sigs)
│                   ├── computeSlice_1_rg (177 sigs)
│                   ├── physical2swizid_rg (372 sigs)
│                   ├── computeRemainingDivision_rg (300 sigs)
│                   ├── computePAKS_rg (235 sigs)
│                   ├── computeSliceAndHshubMapping_rg (73 sigs)
│                   ├── computeQRO_power2_rg (76 sigs)
│                   ├── computeSwizidLtcID_rg (33 sigs)
│                   ├── physical2swizid_bndry_rg (38 sigs)
│                   ├── computeSMCConfig_rg (9 sigs)
│                   ├── computePart_rg (2 sigs)
│                   ├── p2rImpl_Run_i_pd_rsci_inst (19 sigs)
│                   ├── p2rImpl_Run_i_cfg_pd_rsci_inst (19 sigs)
│                   ├── p2rImpl_Run_o_pd_rsci_inst (18 sigs)
│                   ├── p2rImpl_Run_staller_inst (12 sigs)
│                   └── p2rImpl_Run_Run_fsm_inst (6 sigs)
└── u_p2r_test_perf_monitor (SvModule) — 9 sigs
```

### Total Signal Count

| Level | Signals |
|-------|---------|
| TB top-level | 23 |
| Interfaces (cfg, pd in, pd out, debug) | 63 |
| TB wrapper (U_p2r_tb) | 45 |
| Core wrapper (u_physical2raw_core) | 64 |
| HLS top (u_p2r) | 54 |
| HLS impl pipeline | ~2,000+ |
| **Total in FSDB** | **~2,300+** |

### DUT Port Map (u_physical2raw_core)

**19 Inputs:**
| Port | Width | Description |
|------|-------|-------------|
| `clk` | 1 | Clock |
| `reset_` | 1 | Active-low reset |
| `in_valid` | 1 | Input transaction valid |
| `out_busy` | 1 | Output backpressure |
| `physaddr[51:7]` | 45 | Physical address (page-aligned, bits[6:0] dropped) |
| `aperture[1:0]` | 2 | Address aperture |
| `kind[2:0]` | 3 | Client kind |
| `small_page` | 1 | Small page flag |
| `big_page_is_64KB` | 1 | 64KB big page flag |
| `num_active_ltcs[4:0]` | 5 | Number of active LTCs (**should be 8 bits per C model**) |
| `fs2all_num_available_slices_per_ltc_sync[2:0]` | 3 | Slices per LTC (**should be 4 bits per C model**) |
| `fs2all_num_available_slices_per_sys_ltc_sync[1:0]` | 2 | Sys slices per LTC |
| `mem_partition_boundary_table[10:0]` | 11 | Partition boundary |
| `mem_partition_middle_per_slice[19:0]` | 20 | Partition middle |
| `secure_top[22:0]` | 23 | Secure top address (**should be 24 bits — ROOT CAUSE BUG**) |
| `hshub_connection_cfg[2:0]` | 3 | HSHUB connection config (**should be 10 bits per C model**) |
| `remote_swizid[3:0]` | 4 | Remote swizzle ID |
| `alternate_num_ltcs[4:0]` | 5 | Alternate LTC count (tied off) |
| `use_alternate_num_ltcs` | 1 | Use alternate (tied off) |

**10 Outputs:**
| Port | Width | Description |
|------|-------|-------------|
| `out_valid` | 1 | Output valid |
| `in_busy` | 1 | Input backpressure |
| `dst_node_id[5:0]` | 6 | Destination node ID (**HLS produces 9 bits, truncated**) |
| `dst_port_id[1:0]` | 2 | Destination port/slice (**HLS produces 3 bits, truncated**) |
| `dst_hshub_id[1:0]` | 2 | Destination HSHUB ID (**HLS produces 4 bits, truncated**) |
| `xbar_raw_256_byte_aligned[45:0]` | 46 | Raw address (padr) |
| `mp_local_illegal` | 1 | MP local illegal flag |
| `mp_enabled` | 1 | MP enabled (hardcoded 0) |
| `mp_local_eq_remote` | 1 | MP local=remote (hardcoded 0) |
| `mp_req_swizid_p3[3:0]` | 4 | Request swizzle ID |

### HLS Pipeline Architecture (from waveform hierarchy)

The HLS core (`p2rImpl_Run_inst`) has a **multi-stage pipeline** with these computation blocks:

1. **`physical2swizid_bndry_rg`** (38 sigs) — Computes memory partition boundaries and no-man's-land regions
2. **`physical2swizid_rg`** (372 sigs) — Main swizzle ID computation from physical address
3. **`computeSlice_rg` / `computeSlice_1_rg`** (177 sigs each) — Slice ID computation (two parallel instances)
4. **`computePart_rg`** (2 sigs) — Partition computation
5. **`computeRemainingDivision_rg`** (300 sigs) — Division remainder for address mapping
6. **`computePAKS_rg`** (235 sigs) — Partition address key/stride computation
7. **`computeQRO_power2_rg`** (76 sigs) — Power-of-2 quotient/remainder optimization
8. **`computeSwizidLtcID_rg`** (33 sigs) — Final swizzle ID to LTC ID mapping
9. **`computeSliceAndHshubMapping_rg`** (73 sigs) — Slice + HSHUB mapping
10. **`computeSMCConfig_rg`** (9 sigs) — SMC configuration

I/O FIFOs:
- **`i_pd_rsci_inst`** — Input data FIFO (valid/ready handshake)
- **`i_cfg_pd_rsci_inst`** — Config input FIFO (valid/ready handshake)
- **`o_pd_rsci_inst`** — Output FIFO
- **`staller_inst`** — Pipeline stall control
- **`Run_fsm_inst`** — Pipeline FSM controller

### Timing Characteristics (from waveform)

| Parameter | Value |
|-----------|-------|
| Clock period | 10ns (100MHz) |
| Reset release | t=255ns |
| First input valid | t=385ns |
| First output valid | t=425ns |
| Pipeline latency | 4 clock cycles (40ns) |
| Throughput | 1 transaction / 2 cycles (input every other cycle) |
| Clock transitions (full sim) | 4459 |
| Total simulation time | 22.415us |
| Total output transactions | ~87 (from VCT iteration on hls_nodeId) |

### Interface Protocols

| Interface | Bus Width | Protocol | Fields |
|-----------|-----------|----------|--------|
| `i_pd` (data in) | 151 bits | valid/ready | address(52), aperture(2), kind(3), small_page(1), big64k(1), memPartMid(20), memPartBnd(11), memPartSec(24), connCfg(32), remoteSwiz(4), l2bypass(1) |
| `i_cfg_pd` (config in) | 20 bits | valid/ready | numVidLTC(8), numVidSlice(4), numSliceFS(4), numSysSlice(4) |
| `o_pd` (data out) | 67 bits | valid/ready | nodeId(9), sliceId(3), padr(46), hshubID(4), swizid(4), illegal(1) |

---

## 3. Bit-Width Audit (from waveform port analysis)

### Critical Width Mismatches Found

| Signal Path | Wrapper Port | HLS C Model | Lost Bits | Impact |
|-------------|-------------|-------------|-----------|--------|
| **`secure_top`** | **[22:0] = 23 bits** | **`ac_int<24>` = 24 bits** | **bit 23** | **ROOT CAUSE of test failure** |
| `num_active_ltcs` | [4:0] = 5 bits | `ac_int<8>` = 8 bits | bits [7:5] | Values > 31 corrupted |
| `hshub_connection_cfg` | [2:0] = 3 bits | `ac_int<10>` = 10 bits | bits [9:3] | Values > 7 corrupted |
| `dst_node_id` | [5:0] = 6 bits | `ac_int<9>` = 9 bits | bits [8:6] | nodeId > 63 truncated |
| `dst_port_id` | [1:0] = 2 bits | `ac_int<3>` = 3 bits | bit [2] | sliceId > 3 truncated |
| `dst_hshub_id` | [1:0] = 2 bits | `ac_int<4>` = 4 bits | bits [3:2] | hshubID > 3 truncated |
| `fs2all_num_available_slices_per_ltc_sync` | [2:0] = 3 bits | `ac_int<4>` numVidSlice | bit [3] | numVidSlice > 7 truncated |

### Confirmed Root Cause

`secure_top[22:0]` in `NV_AMAP_HLS_physical2raw_core.v` and `p2r_tb.v` — drops bit 23 of `memPartitionSecTopAddr`. For the failing test, the input value **0x81b67b** (bit 23=1) was truncated to **0x01b67b**, corrupting the memory partitioning computation and producing wrong nodeId, sliceId, and padr.

---

## 4. Skill Update Needed

| Skill | Update | Status |
|-------|--------|--------|
| `verdi-waveform.md` | `SigValueEval.get_edge()` returns `(rc, edge_list)` not `(rc, pos, neg)` when `returnDualEdge=True` | TODO |
| `verdi-rca.md` | Added Section 11: Systematic VMOD/HLS Debug Methodology (10-step flow) | DONE |
| Memory (feedback) | Saved: bit-width audit should be priority #1 for HLS wrapper bugs | DONE |
