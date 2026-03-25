#!/bin/bash
# verdi_exec.sh — Execute Python code with Verdi NPI environment
#
# Usage:
#   verdi_exec.sh [--verdi-home <path>] [--timeout <secs>] <script.py> [args...]
#   echo "python code" | verdi_exec.sh [--verdi-home <path>] [--timeout <secs>]
#
# Verdi version detection (if --verdi-home not specified):
#   1. $VERDI_HOME environment variable
#   2. Latest stable version in /home/tools/debussy/verdi3_*
#      (excludes Beta, sorts by version string)

set -euo pipefail

VERDI_HOME_ARG=""
TIMEOUT=120
SCRIPT=""
SCRIPT_ARGS=()

# Parse our arguments (stop at first non-option = script path)
while [[ $# -gt 0 ]]; do
    case $1 in
        --verdi-home)
            VERDI_HOME_ARG="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        *)
            SCRIPT="$1"
            shift
            SCRIPT_ARGS=("$@")
            break
            ;;
    esac
done

# Detect Verdi home
if [[ -n "$VERDI_HOME_ARG" ]]; then
    VERDI_HOME="$VERDI_HOME_ARG"
elif [[ -n "${VERDI_HOME:-}" ]]; then
    VERDI_HOME="$VERDI_HOME"
else
    # Auto-detect: latest stable version with YYYY.MM naming (exclude Beta)
    # Prefer YYYY.MM format (modern Synopsys convention) over legacy YYYYMMDD
    VERDI_HOME=$(ls -d /home/tools/debussy/verdi3_[0-9][0-9][0-9][0-9].[0-9]* 2>/dev/null \
        | grep -vi beta \
        | sort -V \
        | tail -1)
    # Fall back to any verdi3 installation if no YYYY.MM found
    if [[ -z "$VERDI_HOME" ]]; then
        VERDI_HOME=$(ls -d /home/tools/debussy/verdi3_* 2>/dev/null \
            | grep -vi beta \
            | sort -V \
            | tail -1)
    fi
    if [[ -z "$VERDI_HOME" ]]; then
        echo "ERROR: No Verdi installation found" >&2
        exit 1
    fi
fi

# Detect bundled Python (prefer python-3.11, fall back to Python/bin/python3)
PYTHON=""
for candidate in \
    "${VERDI_HOME}/platform/linux64/python-3.11/bin/python3" \
    "${VERDI_HOME}/platform/linux64/Python/bin/python3"; do
    if [[ -x "$candidate" ]]; then
        PYTHON="$candidate"
        break
    fi
done
if [[ -z "$PYTHON" ]]; then
    echo "ERROR: No bundled Python found in ${VERDI_HOME}/platform/linux64/" >&2
    exit 1
fi

# Warn about license
if [[ -z "${SNPSLMD_LICENSE_FILE:-}" ]] && [[ -z "${LM_LICENSE_FILE:-}" ]]; then
    echo "WARNING: SNPSLMD_LICENSE_FILE not set — NPI may fail with license errors" >&2
fi

# Set environment
export VERDI_HOME
export LD_LIBRARY_PATH="${VERDI_HOME}/share/NPI/lib/linux64:${VERDI_HOME}/platform/linux64/bin:${LD_LIBRARY_PATH:-}"
export PYTHONPATH="${VERDI_HOME}/share/NPI/python:${PYTHONPATH:-}"

echo "Using Verdi: ${VERDI_HOME}" >&2

# Execute with timeout
if [[ -n "$SCRIPT" ]]; then
    timeout "$TIMEOUT" "$PYTHON" "$SCRIPT" "${SCRIPT_ARGS[@]}"
else
    # Read from stdin — create temp file, clean up on exit
    TMPSCRIPT=$(mktemp /tmp/verdi_exec_XXXXXX.py)
    trap 'rm -f "$TMPSCRIPT"' EXIT
    cat > "$TMPSCRIPT"
    timeout "$TIMEOUT" "$PYTHON" "$TMPSCRIPT"
fi
