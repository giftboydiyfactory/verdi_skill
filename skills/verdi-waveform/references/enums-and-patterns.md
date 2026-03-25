## 14. Enums

### VctFormat_e (Value Format)

| Name | Value | Use |
|------|-------|-----|
| BinStrVal | 0 | Binary string (e.g. `"01xz"`) |
| OctStrVal | 1 | Octal string |
| DecStrVal | 2 | Decimal string |
| HexStrVal | 3 | Hex string — **best default for digital** |
| SintVal | 4 | Signed integer |
| UintVal | 5 | Unsigned integer |
| RealVal | 6 | Float — **use for analog signals** |
| StringVal | 7 | String |
| EnumStrVal | 8 | Enum name string |
| Sint64Val | 9 | Signed 64-bit integer |
| Uint64Val | 10 | Unsigned 64-bit integer |
| ObjTypeVal | 11 | Native object type |

### ScopeType_e

| Name | Value |
|------|-------|
| SvModule | 0 |
| SvTask | 1 |
| SvFunction | 2 |
| SvBegin | 3 |
| SvFork | 4 |
| SvGenerate | 5 |
| SvInterface | 6 |
| SvInterfacePort | 7 |
| SvModport | 8 |
| SvModportPort | 9 |
| VhArchitecture | 10 |
| VhProcedure | 11 |
| VhFunction | 12 |
| VhProcess | 13 |
| VhBlock | 14 |
| VhGenerate | 15 |
| ScModule | 16 |
| Spice | 17 |
| PwScope | 18 |
| PwDomain | 19 |
| PwLsGroup | 20 |
| PwLsState | 21 |
| PwLsTransition | 22 |
| PwLsArc | 23 |
| PwLsRetention | 24 |
| PwLsIsolation | 25 |
| PwLsStrategy | 26 |
| Unknown | 27 |

### DirType_e

| Name | Value |
|------|-------|
| DirNone | 0 |
| DirInput | 1 |
| DirOutput | 2 |
| DirInout | 3 |

### SigAssertionType_e

| Name | Value |
|------|-------|
| Assert | 0 |
| Assume | 1 |
| Cover | 2 |
| Restrict | 3 |
| Unknown | 4 |

### SigCompositeType_e

| Name | Value |
|------|-------|
| Array | 0 |
| Struct | 1 |
| Union | 2 |
| TaggedUnion | 3 |
| Record | 4 |
| ClassObject | 5 |
| DynamicArray | 6 |
| QueueArray | 7 |
| AssociativeArray | 8 |

### SigPowerType_e

| Name | Value |
|------|-------|
| DomainState | 0 |
| ... | 1-13 |
| Unknown | 14 |

### SigSpiceType_e

| Name | Value |
|------|-------|
| SpNone | 0 |
| Logic | 1 |
| Voltage | 2 |
| AvgRmsCurrent | 3 |
| Mathematics | 4 |
| InstantaneousCurrent | 5 |
| DiDt | 6 |
| Power | 7 |

### ForceTag_e

| Name | Value |
|------|-------|
| InitialForce | 0 |
| Force | 1 |
| Release | 2 |
| Deposit | 3 |
| Unknown | 4 |

### ForceSource_e

| Name | Value |
|------|-------|
| Design | 0 |
| External | 1 |
| Unknown | 2 |

### WaveL1RC_e (Return Codes)

| Name | Value | Meaning |
|------|-------|---------|
| SUCCESS | 0 | Operation succeeded |
| FILE_DOES_NOT_EXIST | 10 | FSDB file not found |
| NO_WAVEFORM_TIMEINFO | 20 | No time information in file |
| UNSUTIABLE_TIMERANGE | 21 | Invalid time range |
| NO_IDENTIFIED_SIGNAME | 30 | Signal name not recognized |
| EVALUATOR_ERROR | 31 | Expression evaluation failed |
| SIG_NOT_FOUND | 40 | Signal not found in FSDB |
| SIG_HAS_MEMBER | 41 | Signal is composite — use member_list() |
| SIG_NO_SIZE | 42 | Signal has no bit width |
| SIG_IS_REAL_OR_STR | 43 | Signal is real or string type |
| NO_SIG_VALUE | 50 | No value data for signal |
| OTHERS | 99 | Unclassified error |

## 15. Common Patterns (Decision Tree)

| Goal | API to use |
|------|-----------|
| Quick check at one time | `sig_value_at()` |
| Value history over a range | `sig_value_between()` |
| Multiple signals at same time | `sig_vec_value_at()` |
| Find when X appears | `sig_find_x_forward()` / `sig_find_x_backward()` |
| Find specific value | `sig_find_value_forward()` / `sig_find_value_backward()` |
| Count transitions | `sig_vc_count()` |
| Fine-grained traversal | VCT via `sig.create_vct()` |
| Multi-signal bulk scan | `TimeBasedHandle` iterator |
| Evaluate expressions | `SigValueEval` |
| Edge detection | `SigValueEval.get_edge()` |
| Large FSDB, limited window | `file.load_vc_by_range()` first |

## 16. Pitfalls

1. **MUST release VCT handles** — call `vct.release()` when done. Leaked handles cause memory issues and eventual segfault.
2. **MUST call `npisys.end()`** — see the `verdi-env` skill for initialization/teardown requirements.
3. **Composite signals** — `sig_value_at()` on a signal where `has_member()` is True will fail. Use `sig.member_list()` to get leaf signals first.
4. **Use HexStrVal for digital** — `VctFormat_e.HexStrVal` is the best default for digital signals. Use `RealVal` for analog.
5. **`goto_time(t)` semantics** — jumps to the last value change AT OR BEFORE `t`, not exactly at `t`. The value returned is what the signal holds at time `t`.
6. **Time units** — all time values are in the file's internal time units. Use `convert_time_in()` and `convert_time_out()` to translate between ns/ps/fs and internal units.
7. **Memory with large FSDB** — for multi-GB FSDB files, use `load_vc_by_range()` to load only the needed time window before creating VCT iterators.
