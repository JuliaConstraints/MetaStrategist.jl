# Canonical receipt allocation qualification — 8 October 2026

Baseline MetaStrategist: `3c6ad5b057af4910bed99412ba24f7bc8d329587`.
Canonical identity encoding now streams into one buffer instead of recursively
joining intermediate strings. Its cold, value-driven writer does not specialize
on every nested tuple shape. Type tags, exact floating-point bits, UTF-8 lengths,
sorted NamedTuple keys, tuple boundaries and absolute-path rejection are
preserved. Receipt identity and mutable-resource ownership contracts are unchanged.

`receipt_scenarios.jl` provides a deterministic portable preparation description
with 64 source descriptors and 32 evaluator descriptions. Its 8,492-byte frozen
encoding has SHA-256
`25a7266a635bbf302e08020924a6ff7c4095da747183105bd127994293632f2e`.
Both direct encoding and real `preparation_receipt` construction verify this
frozen golden identity. Each operation repeats the requested work 32 times.

Julia 1.13.1; affinity 0,2 (two physical cores); Julia threads 2, GC threads 1,
BLAS/OpenMP threads 1, precompile tasks 1. Before/after dependencies match in
temporary offline-resolved environments. Frozen cohort and parent benchmark
files were read-only. These are operational shared-machine observations.

| Warm operation, 32 repetitions | Before bytes / objects | After bytes / objects | Before seconds (3 samples) | After seconds (3 samples) |
|---|---:|---:|---|---|
| canonical encoding | 9,789,984 / 109,250 | 2,457,120 / 44,290 | .006211040, .005409549, .009467443 | .006600677, .006426559, .006435433 |
| preparation receipts | 9,854,064 / 109,667 | 2,521,200 / 44,707 | .010018115, .007014207, .007031832 | .013145984, .006386641, .010492149 |

Object counts are `@timed.gcstats.poolalloc + bigalloc`. Warm observations had
zero measured compile time, collection time and lock conflicts. Allocation
reductions are supported; these samples do not establish a throughput gain.
On the same real owned-unit receipt (14,533 bytes, exact byte equality asserted),
the frozen encoder allocated 436,208 bytes / 4,333 objects and the stream
encoder 116,704 / 1,792. Combined with LocalSearchSolvers's evaluator-description
reuse, typed-unit restoration fell from about 2.78 MB to .25 MB in its ring case.

A narrow shape-specialization experiment used 12 distinct nested NamedTuple
descriptions and asserted original/new byte equality. The frozen public encoder
had 32 method specializations and the new encoder 2. SnoopCompile measured
4.994 s vs .0465 s inclusive inference in that process. The old encoder ran
first and shared compilation/order differ; this is concrete specialization-count
evidence, not a controlled cold latency comparison.

Validation: all 201 MetaStrategist checks passed, including 30 new golden
byte/hash/type-tag/float-bit/key-order/path tests. LocalSearchSolvers's full
11,860-check suite also passed with two-worker private ownership and exact
seeded reset/replay. Full Aqua checks passed after adding test-extra compat.

PerfChecker 1.0.0 analyzers all executed with passing receipt correctness.
JET 0.12.3 reported 57 findings in intentional value-driven serialization and
type display. AllocCheck 0.2.6 reported 17 possible allocations in immutable
receipt construction and canonical conversion; this cold metadata operation
is not statically allocation-free. SnoopCompile 3.2.9 measured .557 s inclusive
first-operation inference. Separate latency source/first/warm scopes were
.0756/.7366/.00472 s. Three GC/lock samples used approximately 2.52 MB each,
with no collection, compilation or lock conflicts. Reachable description size
was 7,724 bytes before and after; state plus the final result was 9,292 bytes.

The heap analyzer captured a redacted after-operation process snapshot of
184,550,462 bytes, SHA-256
`3edabe24acd7c1ddcb991beee67ca308d8f4677be5678a08483cbc8ca362f057`.
The temporary raw snapshot and reports were removed. This intrusive diagnostic
covers the entire Julia GC heap and excludes native memory; it is not retained
result size or performance evidence. Raw stacks and bulk reports are not committed.

## Reference preparation container ownership

The explicit reference factory path already constructs a fresh `Vector{Any}`.
`instantiate_strategy` now transfers that vector to its ReferenceKernel without
copying it again. An actual-type quota fallback that constructed a typed tuple
still converts that tuple to a fresh reference vector. Factories, capture graph
identity, phase ordering, admission statistics and clone behavior are preserved.

`preparation_scenarios.jl` resolves real effect-ordered strategy templates and
performs 32 reference preparations plus executions per observation. A scalar
sum oracle checks all phases; preparation counts and unchanged admission/fallback
counts are checked independently. The same Julia 1.13.1 diagnostic environment
and CPU 0,2 limits above were used before and after. Baseline MetaStrategist was
`3d891e069e0e9993c7239e3b7091833b6756529c`; only this container-copy source change
differs. All samples had zero measured compilation and collection.

| Phases per preparation | Before bytes / objects | After bytes / objects | Before seconds (3 samples) | After seconds (3 samples) |
|---|---:|---:|---|---|
| 3 | 12,944 / 387 | 9,360 / 291 | .000046549, .000027541, .000032149 | .000014113, .000017961, .000017964 |
| 64 | 75,920 / 2,339 | 56,464 / 2,243 | .000060959, .000069805, .000086542 | .000057082, .000040988, .000037295 |
| 129 | 342,672 / 12,707 | 305,808 / 12,611 | .000860051, .000852041, .000865615 | .000657876, .000679543, .000690687 |

These are small operational matched-work measurements on a shared machine.
All 228 package checks passed, including full Aqua and 27 new checks for fresh
private containers, graph captures, deep cloning, typed-tuple quota fallbacks
and the three phase counts. All four PerfChecker collectors passed the 64-phase
case and agreed on 56,448 bytes / 2,242 objects per operation.

JET reported 12 optimization findings and AllocCheck 129 possible allocations,
including intentional dynamic reference execution and factory-owned objects.
SnoopCompile inclusive inference was .922 s. Separate source/first/warm full
case latency scopes were .074/1.579/.003858 s. Three GC and lock samples had
no collection, compilation or conflicts. Fixture state stayed 4,731 bytes;
state with the final prepared result was 5,881 bytes. The process preparation
service retains admission history by design; this fixture-size observation
does not describe that process-wide history. Raw reports are not committed.
