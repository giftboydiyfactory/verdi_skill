## 11. Systematic VMOD/HLS Debug Methodology

This section captures the end-to-end analysis flow proven on real HLS VMOD testbench failures. Follow this sequence for any TRANSACTION_MISMATCH or data comparison error in HLS-based designs.

### Step 1: Identify the Two FSDBs

VMOD test environments often have multiple FSDB files:
- **Regression FSDB** (small, in test output directory) — the actual failing run
- **Debug FSDB** (larger, in p2r_vmod_test or similar) — may be a different run or reference

Always use the FSDB from the **actual failing test directory** for analysis. Verify by checking the time range covers the error timestamp.

```python
f = waveform.open(fsdb_path)
print(f"Time: {f.min_time()} to {f.max_time()}, scale: {f.scale_unit()}")
# Error at 446ns with 10ps scale → t=44600. Check max_time >= 44600.
```

### Step 2: Parse Error Log — Extract ACTUAL vs EXPECTED Fields

For TRANSACTION_MISMATCH errors, extract every field with its **bit-width** and **value**:

```
ACTUAL   {nodeId (9)=3 sliceId (3)=0 padr (46)=8afab4 ...}
EXPECTED {nodeId (9)=f sliceId (3)=2 padr (46)=115f564 ...}
```

Key info to extract:
- Field names and bit-widths (e.g., `nodeId (9)` = 9-bit field)
- Actual vs expected values for each field
- Which fields MATCH and which MISMATCH
- Error time and transaction index

**Critical**: when ALL or MOST fields mismatch, suspect a fundamental input error (wrong data, wrong config, bit-width truncation), not a logic bug in one specific field.

### Step 3: FSDB Reconnaissance — Map the DUT

Dump the signal hierarchy and identify three signal groups:

```python
waveform.hier_tree_dump_sig(f, "/tmp/sigs.txt", expand=1)
```

1. **Input interface signals** — `i_pd_rsc_dat`, `i_pd_rsc_vld`, `i_pd_rsc_rdy` and unpacked fields
2. **Output interface signals** — `o_pd_rsc_dat`, `o_pd_rsc_vld`, `o_pd_rsc_rdy` and unpacked fields
3. **DUT internal signals** — pipeline stages, intermediate computations, config registers

### Step 4: Locate the First Output Transaction

Find when `o_pd_rsc_vld` first goes high and read ALL output fields at that time:

```python
changes = waveform.sig_value_between(f, "...o_pd_rsc_vld", 0, f.max_time(), fmt)
for t, v in changes:
    if v == '1':
        # Read all output fields at time t
        nodeId = waveform.sig_value_at(f, "...nodeId", t, fmt)
        # ... etc
```

Verify: do the waveform values match the scoreboard's ACTUAL values? They should be identical. If not, the wrong FSDB is being analyzed or wrong signal.

### Step 5: Trace Input → Output Pipeline Timing

Build a timeline showing when inputs arrive and when outputs emerge:

```python
# Check input valid transitions
in_vld = waveform.sig_value_between(f, "...in_valid", 0, max_t, fmt)
# Check output valid transitions
out_vld = waveform.sig_value_between(f, "...out_valid", 0, max_t, fmt)
```

Determine:
- **Pipeline latency**: how many cycles from `in_valid` to `out_valid`?
- **Which input produced which output**: match by counting transaction order
- **Config timing**: does config change between input acceptance and output production?

### Step 6: Decode Packed Data Buses

For packed interfaces (`rsc_dat` buses), decode field-by-field using the HESS interface definition:

```python
dat_bin = waveform.sig_value_at(f, "...i_pd_rsc_dat", t, waveform.VctFormat_e.BinStrVal)
dat = int(dat_bin, 2)
address     = (dat >>  0) & ((1 << 52) - 1)
aperture    = (dat >> 52) & ((1 <<  2) - 1)
clientkind  = (dat >> 54) & ((1 <<  3) - 1)
# ... decode all fields per interface spec
```

**Compare decoded values against the waveform's unpacked signals.** Any discrepancy reveals a packing/unpacking bug.

### Step 7: Bit-Width Audit — The Most Common HLS Wrapper Bug

**This is the highest-priority check for HLS VMOD failures.** HLS-generated cores have precise bit-widths from the C model (`ac_int<N>`), but hand-written wrappers often have width mismatches.

Audit checklist — for EVERY signal crossing the wrapper boundary:

1. **Read the HLS C model** (`*_impl.h` / `*_hls.h`) to get the golden bit-widths
2. **Read the wrapper RTL** (`*_core.v`, `*_tb.v`) to get the port widths
3. **Check for truncation** at each level:

```
C model width → HLS port width → Wrapper port width → TB extraction width
     N bits    →    N bits      →    M bits (M<N?)   →    K bits (K<M?)
```

Common patterns:
- **Port too narrow**: `input [22:0] secure_top` when C model needs `ac_int<24>` → MSB lost
- **Zero-padding hides the bug**: `assign full_sig = {zeros, narrow_port}` — looks correct but MSB is always 0
- **Truncation in extraction**: `assign narrow = wide[K:0]` drops upper bits silently
- **Width matches but position wrong**: field extracted from wrong bit range in packed bus

**Red flags to grep for:**

```bash
# Find zero-padding (potential truncation hiding)
grep -n "{{.*1'b0.*}}" wrapper.v

# Find bit-range extractions that might truncate
grep -n "\[.*:0\]" wrapper.v

# Compare port widths vs C model widths
grep "input.*\[" wrapper.v | sort
grep "ac_int<" model.h | sort
```

### Step 8: Verify with Waveform — The Smoking Gun

Once a specific bit-width truncation, verify from the waveform:

```python
# Decode the FULL field from the packed bus
dat = int(waveform.sig_value_at(f, "...rsc_dat", t, bfmt), 2)
full_field = (dat >> start_bit) & ((1 << full_width) - 1)

# Read the truncated port value
truncated = int(waveform.sig_value_at(f, "...port_signal", t, hfmt), 16)

print(f"Full field ({full_width}b): 0x{full_field:x}")
print(f"Port value ({port_width}b): 0x{truncated:x}")
print(f"MSB lost: {full_field != truncated}")
```

If `full_field != truncated`, the bug is found. The difference shows exactly which bits are lost.

### Step 9: Confirm Causality — Does the Truncation Explain ALL Mismatches?

A true root cause must explain ALL mismatched output fields, not just one. The memory partitioning logic uses the truncated value to compute nodeId, sliceId, AND padr. If one input is corrupted, all outputs derived from it will be wrong.

Check: do the MATCHING fields (e.g., hshubID=0, mp_local_illegal=0) make sense with the truncated input? Often, fields that happen to be 0 are unaffected by the truncation.

### Step 10: Document the Fix

For bit-width fixes, specify:
1. **Which file and line** has the truncation
2. **Current width** vs **required width**
3. **All signals in the chain** that need widening (port, wire, assignment)
4. **Test data that triggers the bug** (the specific value with the MSB set)

### Summary: HLS VMOD Debug Priority Order

When debugging HLS VMOD test failures:

1. **Bit-width audit FIRST** — most common HLS wrapper bug, highest ROI
2. **Input data alignment** — is the DUT processing the right transaction?
3. **Config synchronization** — are config and data properly paired through the pipeline?
4. **Pipeline timing** — does the output correspond to the expected input?
5. **Logic errors** — actual computation bugs (least common in HLS-generated code)

The HLS core itself is almost always correct (it's generated from verified C). The bugs are in the **hand-written wrappers** that connect the HLS core to the testbench.

---

