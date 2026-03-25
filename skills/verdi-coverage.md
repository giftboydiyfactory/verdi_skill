---
name: verdi-coverage
description: "Complete pynpi.cov API reference for reading VDB coverage databases — line, toggle, FSM, branch, condition, assertion coverage metrics, test management, exclusions, and gap analysis. Use when analyzing VDB coverage data."
---

# Verdi Coverage — pynpi.cov API Reference

## Quick Start

```python
from pynpi import npisys, cov
import sys

npisys.init([sys.argv[0]])
db = cov.open("simv.vdb")
tests = db.test_handles()
merged = tests[0]
for t in tests[1:]:
    merged = cov.merge_test(merged, t)
instances = db.instance_handles()
for inst in instances:
    tm = inst.toggle_metric_handle()
    if tm:
        print(f"{inst.full_name()}: {tm.covered(merged)}/{tm.coverable(merged)}")
        cov.release_handle(tm)
    cov.release_handle(inst)
db.close()
npisys.end()
```

## Database Operations

| Function | Returns | Description |
|----------|---------|-------------|
| `cov.open(name, config_opt=0)` | Database or None | Open a VDB coverage database |
| `db.close()` | int (1=success) | Close the database |
| `db.name()` | str | Database file path |
| `db.type()` | str | Database type identifier |
| `db.test_handles()` | [Test] | All test handles in the database |
| `db.instance_handles()` | [Instance] | Top-level design instances |
| `db.handle_by_name(name)` | Handle or None | Lookup by full hierarchical name |
| `db.test_by_name(name)` | Test or None | Lookup test by name |

## ConfigOpt (for opening VDB)

Use `config_opt` parameter with `cov.open()` to control loading behavior:

| Constant | Value | Description |
|----------|-------|-------------|
| `cov.ConfigOpt.ExclusionInStrictMode` | 1 | Strict exclusion mode |
| `cov.ConfigOpt.LimitedDesign` | 4 | No design hierarchy, only testbench/assertion coverage (faster) |
| `cov.ConfigOpt.NoLoadMetricData` | 8 | Skip metric data loading (faster) |

Combine flags with bitwise OR:

```python
db = cov.open("simv.vdb", cov.ConfigOpt.LimitedDesign | cov.ConfigOpt.NoLoadMetricData)
```

## Test Management

| Function | Returns | Description |
|----------|---------|-------------|
| `cov.merge_test(dst_test, src_test, map_file=None)` | merged Test | Merge two tests into one |
| `test.save_test(name)` | int | Save test data to file |
| `test.unload_test()` | int | Unload test data from memory |
| `test.load_exclude_file(name)` | int | Load exclusion file |
| `test.save_exclude_file(name, mode)` | int | Save exclusion file (mode: `'w'`, `'a'`, `'ws'`, `'as'`) |
| `test.unload_exclusion()` | int | Unload exclusion data |
| `test.assert_metric_handle()` | Handle | Assertion metric for this test |
| `test.testbench_metric_handle()` | Handle | Testbench metric for this test |
| `test.test_info_handles()` | [TestInfo] | Test info metadata handles |
| `test.program_handles()` | [Handle] | Program handles for this test |

## Instance Hierarchy

### Navigation

| Function | Returns | Description |
|----------|---------|-------------|
| `inst.instance_handles()` | [Instance] | Child instances |
| `inst.database_handle()` | Database | Parent database |
| `inst.scope_handle()` | Handle | Scope handle for this instance |

### Metric Accessors

Each returns a Handle or None:

| Function | Coverage Type |
|----------|--------------|
| `inst.line_metric_handle()` | Line coverage |
| `inst.toggle_metric_handle()` | Toggle coverage |
| `inst.fsm_metric_handle()` | FSM coverage |
| `inst.condition_metric_handle()` | Condition coverage |
| `inst.branch_metric_handle()` | Branch coverage |
| `inst.assert_metric_handle()` | Assertion coverage |

## Coverage Metric Interface

All metric handles share this common interface. The optional `test` parameter filters results to a specific test; pass `None` for cumulative.

### Identity and Location

| Function | Returns | Description |
|----------|---------|-------------|
| `hdl.name()` | str | Short name |
| `hdl.type(test=None, is_get_enum=False)` | str or int | Type identifier (enum int if `is_get_enum=True`) |
| `hdl.full_name()` | str | Full hierarchical name |
| `hdl.file_name()` | str | Source file name |
| `hdl.line_no(test=None)` | int | Source line number |

### Coverage Counts

| Function | Returns | Description |
|----------|---------|-------------|
| `hdl.size(test=None)` | int | Total items |
| `hdl.coverable(test=None)` | int | Total coverable items |
| `hdl.covered(test=None)` | int | Number of covered items |
| `hdl.count(test=None)` | int | Hit count |
| `hdl.count_goal(test=None)` | int | Count goal threshold |
| `hdl.status(test=None)` | int | Raw status flags |

### Status Queries

All take a `test` parameter and return int (0 or 1):

| Function | Meaning |
|----------|---------|
| `hdl.has_status_covered(test)` | Item is covered |
| `hdl.has_status_excluded(test)` | Item is excluded |
| `hdl.has_status_unreachable(test)` | Item is unreachable |
| `hdl.has_status_illegal(test)` | Item is illegal |
| `hdl.has_status_proven(test)` | Item is formally proven |
| `hdl.has_status_attempted(test)` | Item is attempted |
| `hdl.has_status_excluded_at_compile_time(test)` | Excluded at compile time |
| `hdl.has_status_excluded_at_report_time(test)` | Excluded at report time |
| `hdl.has_status_partially_excluded(test)` | Partially excluded |
| `hdl.has_status_partially_attempted(test)` | Partially attempted |

### Hierarchy and Properties

| Function | Returns | Description |
|----------|---------|-------------|
| `hdl.child_handles()` | [Handle] | Sub-metrics / bins |
| `hdl.per_instance(test)` | value | Per-instance flag |
| `hdl.is_mda(test)` | value | Multi-dimensional array flag |
| `hdl.is_port(test)` | value | Port flag |
| `hdl.weight(test)` | value | Weight for coverage calculation |
| `hdl.goal(test)` | value | Coverage goal |

## Coverage Item Classes

The following classes represent specific coverage item types returned by `child_handles()`:

- **Line**: Block, StmtBin
- **Toggle**: Signal, SignalBit, ToggleBin
- **FSM**: Fsm, States, Transitions, StateBin, TransBin
- **Condition**: Condition, ConditionBin
- **Branch**: Branch, BranchBin
- **Assertion**: Assert
- **Functional**: Covergroup, Coverpoint, CoverCross, CoverBin

All item classes implement the common Coverage Metric Interface above.

## Assertion Coverage Report

```python
cov.report_assert_coverage(db, file_name, is_hier_view=True, is_show_all=True, is_merge_tests=True)
```

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `db` | Database | required | Coverage database |
| `file_name` | str | required | Output report file path |
| `is_hier_view` | bool | True | Hierarchical view |
| `is_show_all` | bool | True | Show all assertions |
| `is_merge_tests` | bool | True | Merge tests in report |

Returns `bool` — True on success.

## TestInfo

| Function | Returns | Description |
|----------|---------|-------------|
| `testinfo.name()` | str | Test info name |
| `testinfo.find_attribute(key)` | (status, value) | Lookup attribute by key |

## Resource Management

**CRITICAL: You must release ALL handles when done to avoid memory leaks.**

```python
cov.release_handle(hdl)
```

Always use try/finally to ensure cleanup:

```python
inst = db.instance_handles()[0]
try:
    lm = inst.line_metric_handle()
    if lm:
        try:
            print(f"Line coverage: {lm.covered(test)}/{lm.coverable(test)}")
        finally:
            cov.release_handle(lm)
finally:
    cov.release_handle(inst)
```

## Common Patterns

### Coverage Rate Calculation

```python
def coverage_rate(hdl, test=None):
    total = hdl.coverable(test)
    if total == 0:
        return 0.0
    return hdl.covered(test) / total * 100
```

### Gap Analysis — Find Uncovered Bins

```python
def find_gaps(metric_hdl, test):
    gaps = []
    for child in metric_hdl.child_handles():
        try:
            if child.has_status_covered(test) == 0:
                gaps.append({
                    "name": child.full_name(),
                    "file": child.file_name(),
                    "line": child.line_no(test),
                })
        finally:
            cov.release_handle(child)
    return gaps
```

### Multi-Test Merge Before Querying

```python
tests = db.test_handles()
if not tests:
    raise ValueError("No tests found in VDB")
merged = tests[0]
for t in tests[1:]:
    merged = cov.merge_test(merged, t)
# Now query coverage against merged test
```

### Fast Load for Quick Overview

```python
db = cov.open("simv.vdb", cov.ConfigOpt.LimitedDesign | cov.ConfigOpt.NoLoadMetricData)
# Only testbench/assertion coverage available, no design metrics
```
