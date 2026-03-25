# Verdi Skills — AI-Driven Hardware Debug Plugin for Claude Code

A Claude Code plugin that enables AI to autonomously debug hardware simulation failures by reading FSDB waveforms, VDB coverage databases, and KDB design databases via Synopsys Verdi's Python NPI (`pynpi`) API.

## What It Does

Give AI an FSDB waveform + simulation error log, and it will:
1. Parse the error log to identify failure type, timestamp, and signals
2. Open the FSDB and explore the design hierarchy
3. Generate and execute `pynpi` Python code dynamically
4. Trace signals, find X-value origins, compare fmod vs vmod
5. Build a causal chain from root cause to observed failure
6. Report findings with waveform evidence

## Architecture

```
verdi-skills/
├── plugin.json              # Plugin manifest
├── scripts/
│   └── verdi_exec.sh        # Env bootstrap — auto-detects Verdi, sets up Python 3.11
└── skills/
    ├── verdi-debug.md        # Orchestrator — main entry point for RCA
    ├── verdi-env.md          # Environment detection + execution setup
    ├── verdi-waveform.md     # Complete pynpi.waveform API reference (FSDB)
    ├── verdi-coverage.md     # Complete pynpi.cov API reference (VDB)
    ├── verdi-netlist.md      # pynpi.netlist API — driver/load tracing
    ├── verdi-language.md     # pynpi.lang API — RTL source + active trace
    ├── verdi-transaction.md  # Transaction waveform API (AXI/AHB/APB)
    └── verdi-rca.md          # RCA methodology + debug recipes
```

**Design philosophy**: Maximum flexibility — skills teach AI the APIs and debug methodology, then AI dynamically generates Python code for each investigation step. No hardcoded scripts.

## Supported APIs (Tested: 292/293 = 99.7%)

| Category | APIs | Status |
|----------|------|--------|
| Waveform (FSDB) | `sig_value_at`, `sig_value_between`, `sig_find_x_forward/backward`, `sig_find_value_forward/backward`, VCT, VC iterators, `SigValueEval`, memory management | 136/137 |
| Coverage (VDB) | `cov.open`, metrics (line/toggle/FSM/cond/branch/assert), test merge, exclusions, `ConfigOpt` | 156/156 |
| Netlist (KDB) | `trace_driver`, `trace_load`, instance ports, fan-in/fan-out | Tested |
| Language (KDB) | `trace_driver2`, `active_trace_driver`, `find_signal_regex`, source file:line | Tested |
| Transaction | Stream/transaction traversal, protocol extraction | Available |

## Quick Start

### Prerequisites
- Synopsys Verdi 2025.06+ (with Python 3.11 NPI bindings)
- Claude Code with plugin support

### Installation
```bash
# Copy to Claude Code plugins directory
cp -r . ~/.claude/plugins/verdi-skills/
chmod +x ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```

### Usage
In Claude Code, provide an FSDB file path and error description:
```
Debug this simulation failure:
FSDB: /path/to/test.fsdb
Error: UVM_FATAL @ 46555ns: No matching fmod entry for vmod req with src 13 vc 1 gnic2gxbar port 0
```

The `verdi-debug` skill triggers automatically and orchestrates the investigation.

### Manual `verdi_exec.sh` Usage
```bash
# Auto-detect Verdi, execute Python script
~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh /tmp/analysis.py

# Specify Verdi version
~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh --verdi-home /path/to/verdi script.py

# Pipe Python code
echo 'from pynpi import npisys, waveform; ...' | ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh
```

## Debug Methodology (built into skills)

### HLS VMOD Debug (verdi-rca.md Section 11)
1. Bit-width audit FIRST — most common HLS wrapper bug
2. Decode packed data buses field-by-field
3. Compare HLS C model `ac_int<N>` widths vs RTL port widths
4. Verify from waveform: full-width value vs truncated port value

### Full-Stack Debug (verdi-rca.md Section 12)
1. Use FSDB + KDB + VDB together — never read source code manually
2. Systematic signal comparison (all simTop signals, not just suspects)
3. X-value origin tracing with `sig_find_x_forward/backward`
4. KDB `lang.trace_driver2()` for RTL driver chain + source file:line
5. Pipeline stage normalized throughput for perf analysis

### Fmod vs Vmod Debug Recipe
1. Compare fmod (`f_` prefix) vs vmod (`v_` prefix) outputs per-port
2. Check valid timing alignment
3. Trace X contamination backward through pipeline
4. Use KDB to find clock gate control logic

## Real-World Validated

This plugin was validated on real NVIDIA GPU hardware debug cases:
- **p2r (physical2raw) HLS wrapper** — found 1-bit truncation in `secure_top` port (23 bits vs 24 bits needed)
- **gpcarb gnic2xbar perf instability** — found seed-dependent address interleaving causing 55% CV in per-port throughput
- **gpcarb sm2sm fmod/vmod mismatch** — traced X-value origin through fold pipeline to clock gate timing misalignment

## Docs

- [Design Spec](docs/superpowers/specs/2026-03-22-verdi-skills-design.md)
- [Implementation Plan](docs/superpowers/plans/2026-03-22-verdi-skills-implementation.md)
- [API Validation Report](docs/verdi-skills-full-validation-report.md)
