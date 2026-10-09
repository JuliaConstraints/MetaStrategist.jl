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

## Canonical byte-count and key-order allocation

The canonical writer now emits a string's nonnegative decimal byte count
directly into its buffer and sorts Symbol keys directly. Julia's Symbol and
String comparisons use the same byte-lexical order; no per-comparison key
strings are needed. The tags, UTF-8 byte lengths, scalar formatting, absolute
path checks, key order and resulting identities are preserved.

Before source was read from `022c052497d6caf21d71f19b3167dd8c11eca24a` into an
isolated in-memory module. Before and after functions used the same description,
process, resolved dependencies and two-core limits. Both were warmed; sample
order alternated using seed 91, with collection outside the timed operation.
The raw encoding loop discards each string; receipt construction retains its
final result. Both evaluate 32 identical descriptions. All samples had zero
measured compilation and collection.

| Matched operation | Before bytes / objects | After bytes / objects | Before seconds (3 samples) | After seconds (3 samples) |
|---|---:|---:|---|---|
| 32 raw encodings | 2,409,472 / 44,256 | 1,504,256 / 15,968 | .003477889, .003449592, .003430666 | .002387287, .002391183, .002376248 |
| 32 receipt constructions | 2,521,168 / 44,705 | 1,615,952 / 16,417 | .004291643, .004112657, .004007132 | .003124438, .003154983, .003083262 |

The reference 8,492-byte encoding and SHA-256 identity remain unchanged. All
1,030 MetaStrategist checks passed, including full Aqua and 802 new byte-count
boundary, Unicode/ASCII Symbol ordering and canonical key-encoding checks.
These remain operational measurements on a shared machine.

All four PerfChecker collectors passed the canonical case, which retains the
final string. Their independent operation totals agreed on 1,551,872 bytes /
16,000 objects. JET reported 57 optimization findings in intentionally dynamic
serialization/type display; AllocCheck reported 2 possible allocations. These
static findings do not cover every runtime dispatch target, and the measured
operation still allocates. Inclusive SnoopCompile inference was .390 s.
Separate source/first/warm full case latency scopes were .071/.553/.002499 s.
Three GC and lock samples had no collection, compilation or conflicts.
Reachable description state stayed 7,724 bytes, or 16,232 bytes with its final
encoded string. Raw reports and the comparison module were not saved.

The 13,358-byte receipt from a real 32-variable LocalSearchSolvers prepared unit
was byte-identical under the previous and new encoders. All 11,878
LocalSearchSolvers regression checks passed with the new MetaStrategist source.

## Count incoming edges during phase resolution

Resolution now counts incoming ordering edges once and advances the whole ready
batch before collecting its successors. Each new batch retains the original
lexical ordering. This removes repeated scans over every remaining phase while
preserving dependency closure, effect validation, duplicate-edge handling,
cycle diagnostics, snapshots and semantic/shape identities.

`resolution_scenarios.jl` resolves each fixed catalogue sixteen times per
operation: chains of 3/64/129 phases, 64 independent phases, and four fully
connected layers of sixteen phases. Independent expected orders and five pairs
of baseline identity hashes pass before and after. The baseline is
MetaStrategist `f64bfa4d68f3f80b08eee473a3bfc90f56e0fb5d`; LocalSearchSolvers
`dca296e339cbdf617e2645f1871983a134920d80`, CBLS
`2c453ddee7f3af7433573969916caec1918fe8d4` and resolved dependencies are unchanged.
Both environments use the two-core limits above. Collection is requested
outside each timed observation. Compilation time is zero in all warm samples.

| Sixteen resolutions | Before bytes / objects | After bytes / objects | Before seconds (3 samples) | After seconds (3 samples) |
|---|---:|---:|---|---|
| chain, 3 phases | 556,784 / 8,963 | 557,568 / 8,835 | .000989203, .000920043, .000949789 | .000928845, .000873210, .000870873 |
| chain, 64 phases | 26,217,968 / 659,235 | 13,476,608 / 284,115 | .028234098, .028338512, .028249853 | .017648517, .018062823, .018044748 |
| chain, 129 phases | 97,777,136 / 2,791,843 | 32,208,640 / 842,339 | .115115643, .114582794, .114799315 | .042062980, .041843313, .041903248 |
| independent, 64 phases | 12,298,224 / 281,251 | 11,933,952 / 269,235 | .017218059, .017358111, .017496604 | .016643799, .016654314, .017028430 |
| layered, 64 phases | 17,352,688 / 342,835 | 16,698,624 / 322,371 | .022363795, .022292080, .023932284 | .025510363, .021862748, .021598528 |

The smallest chain uses 784 additional bytes per sixteen resolutions for its
edge-count table, despite fewer objects. Timing is operational evidence on a
shared machine, rather than a campaign or hot-kernel throughput result. The
129-phase baseline samples spend .004730/.005085/.005090 s in collection;
other table samples have zero measured collection time.

All 9,767 package checks and full Aqua pass. The 8,737 new checks enumerate all
4,096 directed four-phase graphs, use valid permutations and longest-path depth
as an independent order oracle, verify identities under reversed roots, reject
cycles and cover duplicate dependency/before/after edges. These checks also pass
against the original resolver. Fourteen LocalSearchSolvers checks pass for two
private typed workers, exact reset/replay and original score validation.

All four PerfChecker collectors pass all three 64-phase topologies. To bound
full allocation-profile volume, these collector operations resolve once:
chain 842,328 bytes / 17,758 objects; independent 745,912 / 16,828; layered
1,043,704 / 20,149. BenchmarkTools, Chairmarks and independent allocation-profile
totals agree. Analyzer operations retain sixteen chain resolutions.

JET has 125 findings and AllocCheck 122 through cold dynamic catalogue and
identity construction; this operation is not inference- or allocation-free.
Inclusive SnoopCompile inference is 1.073 s. Separate source/first/warm latency
scopes are .087/1.725/.019298 s. Three GC and lock samples have zero compilation
and lock conflicts; one sample in each analyzer collects (.012372/.016117 s).
Reachable fixture state stays 44,337 bytes, or 52,753 bytes including its final
resolved description, in all three observations. Raw reports are not saved.

## Capability filtering

Compatibility checks now test membership in the original capability sets,
without constructing temporary unions and intersections. Solver requirements
still use problem features and resource provisions; resource requirements still
use problem features and solver provisions. Guidance uses all three provision
sources. The separate union-returning helper still returns a fresh owned set.
Binding enumeration retains input order, duplicate input entries and fresh
result vectors. Current mutable input sets are read on each call.

`capability_scenarios.jl` prepares sixteen solvers, sixteen resources and four
guidance policies. Each operation checks 32,768 combinations. The compatibility
case counts 9,472 acceptances. The binding case performs 32 passes over all four
policies and retains final ordered lists of lengths 128/64/40/64. Independent
fixture-id rules verify both results. Guidance construction is outside timing;
these are admission operations, not solver episode or campaign measurements.

The baseline is MetaStrategist `0b761608726025d2fec402ad18b6e1773045fa2b` in a
temporary source snapshot. LocalSearchSolvers
`bcc516b6fa1d3edc9732bebb38a009719491c8d1`, CBLS
`2c453ddee7f3af7433573969916caec1918fe8d4` and resolved dependencies are unchanged.
Only the MetaStrategist path differs between environments. Both use the
two-core limits above. Collection is requested outside each timed sample;
measured compilation and collection time are zero in all table observations.

| Warm matched operation | Before bytes / objects | After bytes / objects | Before seconds (5 samples) | After seconds (5 samples) |
|---|---:|---:|---|---|
| 32,768 compatibility checks | 27,627,760 / 345,347 | 240 / 3 | .006521991, .006632872, .006604609, .006667561, .006750497 | .000922365, .000988069, .000917204, .000931578, .000935573 |
| 128 binding queries | 28,022,016 / 346,114 | 394,496 / 770 | .006680790, .006649141, .006621608, .006734366, .006949253 | .001088769, .000985650, .001050503, .000999038, .000992810 |

All 22,083 MetaStrategist checks and full Aqua pass. The 12,316 new checks also
pass against the baseline. They enumerate all two-capability problem,
provision, requirement and valid guidance combinations using an independent
bitmask oracle, then check mutations between calls, unchanged input sets,
fresh union results and ordered binding vectors with duplicate inputs.
Fourteen LocalSearchSolvers checks pass for two private typed workers,
exact reset/replay and original score validation.

All four PerfChecker collectors pass both operations. BenchmarkTools,
Chairmarks and independent allocation-profile totals agree on zero bytes /
objects for the concrete compatibility operation, and 394,288 bytes / 769
objects for binding enumeration. Remaining binding allocations own its output
vectors; preparation and default-guidance construction are separate scopes.
JET optimization findings remain zero. AllocCheck falls from nine findings to
zero for the compatibility operation. This does not qualify every caller or
the whole preparation lifecycle as allocation-free.

All nine native analyzer adapters complete. Inclusive SnoopCompile inference
is .107 s. Separate source/first/warm lifecycle latency scopes are
.071/.723/.001051 s. Three GC and lock samples allocate zero bytes, with no
compilation, collection or conflicts. Reachable fixture state stays 45,216
bytes, or 45,224 bytes including its scalar result. The redacted heap snapshot
passes verification and is removed with the raw diagnostic artifacts.
Measurements remain operational evidence on a shared machine.

## Parameter shapes and normalization

Named-tuple shape descriptions now sort their keys once and iterate the sorted
vector while constructing the result. Normalization uses the same vector
iteration, avoiding runtime tuple iteration and temporary comparison strings.
Core scalar shape labels use their type names; custom and parameterized types
retain Julia's complete type display. Key order, scalar values, floating-point
bits and semantic/shape identities remain unchanged.

`parameter_scenarios.jl` builds thirty-two descriptions from the existing
64-file receipt fixture. Recursive key-order checks and two baseline hashes
verify the final outputs: a 3,292-byte shape encoding and the original
8,492-byte normalized encoding. The included receipt fixture is declared as
a PerfChecker input fingerprint. Preparation and verification are outside
the measured operation.

The baseline is MetaStrategist `c2f0a345eb20f211b116a6aa1629cde79c763b49` in
a temporary source snapshot. LocalSearchSolvers
`bcc516b6fa1d3edc9732bebb38a009719491c8d1`, CBLS
`2c453ddee7f3af7433573969916caec1918fe8d4` and resolved dependencies are
unchanged. Only the MetaStrategist path differs. Both environments use the
two-core limits above; collection occurs outside timed observations.
Compilation and collection time are zero in all table samples.

| Thirty-two constructions | Before bytes / objects | After bytes / objects | Before seconds (5 samples) | After seconds (5 samples) |
|---|---:|---:|---|---|
| parameter shapes | 4,242,688 / 73,728 | 2,681,600 / 32,000 | .003570501, .003542525, .003577777, .003492733, .003460954 | .001971360, .001982085, .001981668, .001991126, .001961623 |
| normalized parameters | 3,084,544 / 37,504 | 2,506,496 / 26,208 | .002491414, .002506974, .002440936, .002528793, .002494660 | .001872072, .001906098, .001926788, .001914887, .001908592 |

All 24,037 package checks and full Aqua pass. The 1,954 new checks also pass
against the baseline. They cover every core scalar label, the generic custom
type fallback, nested empty structures, Unicode/ASCII key pairs, signed zero
and NaN payloads, using a separate string-sorted structural reference and exact
canonical byte comparisons. Fourteen LocalSearchSolvers checks pass for two
private workers and exact reset/replay. Shape and normalization of an actual
prepared-unit receipt are structurally and byte-identical under both helper
versions: 4,176 and 13,358 encoded bytes respectively.

All four PerfChecker collectors pass both operations. BenchmarkTools,
Chairmarks and independent allocation-profile totals agree on the after
byte/object counts in the table. Shape JET optimization findings fall from
35 to 12, and AllocCheck
findings from 32 to 23. Normalization has a static-analysis tradeoff: JET
findings rise from 2 to 12 and AllocCheck findings from 13 to 25, despite the
measured runtime and allocation improvement. These cold dynamic operations
remain inference- and allocation-bearing; no universal inference-free claim
is made.

All nine native analyzer adapters complete for the shape case. Inclusive
SnoopCompile inference is 3.538 s. Source/first/warm full lifecycle latency
scopes are .077/1.908/.005773 s. Three GC and lock samples each allocate
2,681,600 bytes, with no compilation, collection or conflicts. Reachable
fixture state stays 7,724 bytes, or 11,723 bytes including its final shape
description. The redacted heap snapshot passes verification and is removed
with the raw diagnostic artifacts. Timing remains operational evidence on
a shared machine.

## Resource-effect checks during resolution

The resolver checks resource-effect tuples directly instead of constructing
three dictionaries of temporary sets. A function boundary specializes their
concrete tuple contents. Index iteration avoids copying every remaining role
suffix. Successful resource and capability checks no longer construct sets;
their existing error messages retain the original set construction.
Ordering, invalidation/write precedence, ownership and canonical descriptions
remain unchanged. Factories still do not execute during resolution.

The isolated baseline is MetaStrategist
`ba019deede736e436e893be187e517fd5a1ce23c`. Both environments contain identical
LocalSearchSolvers `bcc516b6fa1d3edc9732bebb38a009719491c8d1`, CBLS
`93e83b62935a24b193bd1566016bb86a8ff16b3a`, frozen shared packages and diagnostic
dependencies; manifest comparison finds only the MetaStrategist source-path
difference. Both use CPUs 0 and 2, two Julia threads, one GC thread and one
BLAS/OpenMP worker. Collection occurs outside five warmed observations; measured
compilation and collection time are zero.

`resource_scenarios.jl` includes the original resolution fixture as an explicit
fingerprinted input. Shared-state chains invalidate and rewrite their state,
wide plans write disjoint resources, and layered plans read sixteen predecessor
resources. Capability dependencies are active. All ten plain/resource cases
retain their semantic keys, shape keys and byte-identical canonical snapshots.
The new resource fixtures check fixed prior-version hash oracles.

| 16 warmed resolutions | Before bytes / objects | After bytes / objects |
|---|---:|---:|
| plain chain, 3 phases | 546,752 / 8,546 | 431,808 / 6,690 |
| plain chain, 64 phases | 13,247,168 / 277,970 | 8,849,856 / 118,722 |
| plain chain, 129 phases | 31,746,240 / 829,954 | 18,235,072 / 241,154 |
| plain wide, 64 phases | 11,704,512 / 263,090 | 7,307,200 / 103,842 |
| plain layers, 64 phases | 16,469,184 / 316,226 | 12,071,872 / 156,978 |
| resource chain, 3 phases | 610,240 / 9,778 | 496,832 / 8,066 |
| resource chain, 64 phases | 13,397,696 / 235,426 | 10,032,576 / 141,714 |
| resource chain, 129 phases | 29,888,320 / 609,634 | 20,604,224 / 287,090 |
| resource wide, 64 phases | 12,785,344 / 281,106 | 10,468,800 / 251,906 |
| resource layers, 64 phases | 24,029,376 / 361,698 | 21,086,144 / 317,906 |

The active 129-phase chain spans .040564–.042150 s before and
.033562–.034319 s after. Active 64-phase wide/layer plans span
.019199–.020561/.029679–.030066 s before and
.015016–.015552/.025668–.025902 s after. These are fixed-work observations on a
shared machine, without an application-throughput claim.

All 61,815 MetaStrategist regressions, including full Aqua, pass. The 37,778 new
checks also pass against the prior source: every combination of two-resource
reads/writes/invalidation with three ordering policies, capability availability,
ownership errors and factory non-execution. A separate prior/current resolver
comparison matches 16,993 outcomes exactly: 9,329 exception types/messages and
7,664 canonical snapshots/shape keys. Existing exhaustive four-phase graph
oracles remain intact. LSS's fourteen private-worker ownership/reset/replay
checks pass with the final implementation.

All four native collectors pass all five resource cases and the plain
129-phase case. BenchmarkTools, Chairmarks and full allocation profiles agree
on one-resolution totals: resource chain 3/64/129 uses
31,096/627,080/1,287,808 bytes and 505/8,858/17,944 objects; wide/layers uses
654,344/1,317,928 bytes and 15,745/19,870 objects. The plain 129-phase operation
uses 1,139,736 bytes and 15,073 objects. Collector time outliers remain visible
in the raw run; only aggregate allocation evidence is retained here.

All nine native diagnostic adapters complete for the active 64-phase chain.
JET findings fall from 125 to 96; AllocCheck findings from 124 to 95. This cold
operation retains dynamic inference and allocations. Inclusive SnoopCompile
inference is .987 s. Separate load/first/warm lifecycle latency is
.098/1.522/.002514 s. Three GC and lock observations each allocate 627,080
bytes, without compilation, collection or observed conflicts. Reachable fixture
state stays 46,913 bytes, or 55,345 with the result. The verified redacted heap
snapshot and raw reports are removed.

## Portable checkpoint encoding, 2026-10-09

The strategy and preparation-receipt codec now validates the complete immutable
value once before recursively encoding it. The original portable validator,
scalar tags, exact float bits, key order, archive schema, integrity checks and
exclusive writes are retained. Previously, every child repeated validation of
its subtree. This change concerns cold checkpoint work, not search throughput.

The comparison uses MetaStrategist `4ae6f246b9a131b1d5b8c17b850b9477a426961d`
in a temporary source checkout. Dependency versions and paths match except for
MetaStrategist; LocalSearchSolvers is `bcc516b` and CBLS is `93e83b6`.
Julia 1.13.1 uses CPUs 0/2, two Julia threads and one GC thread. Each exact
operation is warmed three times before five observations. Compilation and
recompilation totals are zero in every measured row.

| Fixture, 32 encodings | Before bytes / objects | After bytes / objects |
| --- | ---: | ---: |
| Preparation receipt, 64 source files | 16,470,016 / 197,792 | 8,922,624 / 99,520 |
| Three-phase strategy | 3,168,768 / 51,936 | 2,369,024 / 35,904 |
| 129-phase strategy | 152,444,416 / 2,060,480 | 118,934,528 / 1,394,976 |

Receipt encoding takes .013413–.014415 s before and .003943–.004229 s after;
129-phase encoding takes .108925–.110867 s before and .058375–.074283 s after.
The large case includes GC in both processes. These are matched-work observations
on a shared machine, not controlled application throughput estimates.

Four complete write/read/verify operations also allocate less: the receipt
uses 6,914,880–6,917,544 bytes before and 5,971,456–5,974,120 after; the small
strategy uses 1,368,448–1,369,056 before and 1,268,288–1,268,992 after; the large
strategy uses 61,513,376–61,529,800 before and 57,324,640–57,342,064 after.
Write timing ranges overlap. All three files are byte-identical to the previous
implementation; their fixed SHA-256 identities are checked in `archive_scenarios.jl`.
Every temporary archive directory is removed in a `finally` block.

The new 969 checks pass before and after, including exact integer types, signed
zero, infinity and NaN payloads, Unicode, nested portable-validation errors and
archive history preservation. The full updated suite passes 62,784 assertions
including Aqua. All four native collectors pass all six encode/write cases.
For one encoding, BenchmarkTools, Chairmarks and full allocation profiles agree
on receipt/small/large totals of 278,832/74,032/3,722,976 bytes and
3,110/1,122/43,594 objects. Full writes retain expected filesystem and decoding
allocations; the fresh collector boundary differs slightly from repeated direct
measurements.

All nine native diagnostic adapters complete for receipt encoding. JET retains
82 findings; AllocCheck falls from 361 to 309. This codec remains dynamic and
allocating. Inclusive inference is 3.935 s; load/first/warm case latency is
.094/3.500/.001692 s. Three GC observations allocate 278,832 bytes each, with
zero compilation and one process-wide collection in the first observation;
three lock observations see no conflicts. Reachable fixture memory stays
9,300 bytes, or 121,450 with the fresh encoded result. The verified redacted
heap snapshot and temporary reports are removed.
