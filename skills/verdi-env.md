---
name: verdi-env
description: "Verdi NPI environment setup — detects Verdi version, configures Python execution environment for pynpi. Use when about to execute any pynpi code against FSDB/VDB files."
---

# Verdi NPI Environment Setup

This skill teaches how to set up the pynpi execution environment for running Python scripts against Verdi's NPI (Native Programming Interface). All pynpi scripts require a correctly configured Verdi environment with proper Python paths, shared libraries, and resource lifecycle management.

## Verdi Installation Locations

On NVIDIA systems, Verdi is installed under `/home/tools/debussy/verdi3_*`. The latest stable release is typically `verdi3_2025.06-SP2-2`.

## Version Detection Priority

When determining which Verdi installation to use, follow this order:

1. **User-specified version** — if the user explicitly provides a Verdi path, use it.
2. **`$VERDI_HOME` environment variable** — WARNING: this may point to an older version that lacks the bundled Python 3.11. Always verify before using.
3. **Auto-detect** — scan `/home/tools/debussy/verdi3_*`, sort by version, and pick the latest stable release. Exclude any directory containing `Beta` in its name.
4. **Verify Python exists** — confirm that `{VERDI_HOME}/platform/linux64/python-3.11/bin/python3` is present. If it is not, the selected Verdi version is too old and cannot run pynpi.

## Using verdi_exec.sh (PREFERRED Method)

The `verdi_exec.sh` wrapper script handles all environment setup automatically. Always prefer this over manual configuration.

```bash
# Execute a script file
~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh /tmp/analysis.py

# Execute code from stdin
echo '<python code>' | ~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh

# Specify Verdi version
~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh --verdi-home /home/tools/debussy/verdi3_2025.06-SP2-2 /tmp/analysis.py

# Custom timeout (default 120s)
~/.claude/plugins/verdi-skills/scripts/verdi_exec.sh --timeout 300 /tmp/analysis.py
```

## Python Boilerplate Template

When NOT using `verdi_exec.sh`, all pynpi scripts MUST include this boilerplate:

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

# === Your analysis code here ===

npisys.end()  # MUST call to release all NPI resources
```

Replace `{detected_verdi_home}` with the actual Verdi installation path determined by the version detection priority above.

## Resource Cleanup Rules (CRITICAL)

Failure to release NPI resources causes memory leaks, license hogging, and segfaults.

- **Always** call `npisys.end()` at the end of every script.
- **Always** call `vct.release()` after using VCT (Value Change Trace) handles.
- **Always** call `ft.release()` after using FT (FSDB Traversal) handles.
- **Always** call `trt.release()` after using transaction traverse handles.
- **Always** call `cov.release_handle(hdl)` after using coverage handles.
- **Use try/finally** to ensure cleanup runs even when errors occur:

```python
from pynpi import npisys, waveform

npisys.init([sys.argv[0]])
ft = None
try:
    ft = waveform.open("dump.fsdb")
    # ... analysis code ...
finally:
    if ft is not None:
        ft.release()
    npisys.end()
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `ImportError: _npisys` | `LD_LIBRARY_PATH` is wrong or missing Verdi's NPI libs | Ensure `{VERDI_HOME}/share/NPI/lib/linux64` and `{VERDI_HOME}/platform/linux64/bin` are in `LD_LIBRARY_PATH` |
| License errors | License server not configured | Set the `SNPSLMD_LICENSE_FILE` environment variable |
| Python version mismatch | Using system Python instead of Verdi's bundled interpreter | MUST use `{VERDI_HOME}/platform/linux64/python-3.11/bin/python3` — never system Python |
| `npisys.init()` returns 0 | Incorrect argv format | Must pass a list with at least one element (the program name) |
| Segfault | Forgot to release handles, or called `npisys.end()` too early | Release all handles before `npisys.end()`; use try/finally for safety |

## Available pynpi Modules (Quick Reference)

| Import | Purpose |
|--------|---------|
| `from pynpi import waveform` | FSDB waveform reading |
| `from pynpi import cov` | VDB coverage analysis |
| `from pynpi import netlist` | Design netlist traversal |
| `from pynpi import lang` | RTL language model and signal tracing |
| `from pynpi import text` | Source text manipulation |
| `from pynpi import sdb` | Static design database |
| `from pynpi import waveformw` | Waveform writer |
