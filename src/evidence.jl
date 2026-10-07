"""Pointer to an immutable evidence artifact such as a PerfChecker run bundle."""
struct EvidenceReference
    schema::String
    location::String
    digest::Union{Nothing,String}

    function EvidenceReference(
        schema::AbstractString,
        location::AbstractString;
        digest = nothing,
    )
        isempty(schema) && throw(ArgumentError("an evidence schema cannot be empty"))
        isempty(location) && throw(ArgumentError("an evidence location cannot be empty"))
        normalized_digest = isnothing(digest) ? nothing : String(digest)
        return new(String(schema), String(location), normalized_digest)
    end
end

"""Selector-facing summary linked to complete external evidence."""
struct RunEvidence
    plan_id::Symbol
    problem_fingerprint::String
    status::Symbol
    metrics::Dict{Symbol,Float64}
    references::Vector{EvidenceReference}
    context::Dict{Symbol,Any}
end

function RunEvidence(
    plan_id::Symbol,
    problem_fingerprint::AbstractString,
    status::Symbol;
    metrics = Dict{Symbol,Float64}(),
    references = EvidenceReference[],
    context = Dict{Symbol,Any}(),
)
    normalized_metrics = Dict{Symbol,Float64}()
    for (key, raw_value) in pairs(metrics)
        value = Float64(raw_value)
        isfinite(value) || throw(ArgumentError("evidence metrics must be finite"))
        normalized_metrics[Symbol(key)] = value
    end
    return RunEvidence(
        plan_id,
        String(problem_fingerprint),
        status,
        normalized_metrics,
        EvidenceReference[references...],
        Dict{Symbol,Any}(Symbol(key) => value for (key, value) in pairs(context)),
    )
end

abstract type AbstractEvidenceStore end

"""Append one validated selector-facing record to an evidence store."""
function append_evidence! end

"""Query selector-facing records without loading the referenced measurement bundles."""
function query_evidence end

"""Dependency-free store used for tests and small interactive sessions."""
mutable struct InMemoryEvidenceStore <: AbstractEvidenceStore
    records::Vector{RunEvidence}
end

InMemoryEvidenceStore() = InMemoryEvidenceStore(RunEvidence[])

function append_evidence!(store::InMemoryEvidenceStore, evidence::RunEvidence)
    push!(store.records, evidence)
    return evidence
end

function query_evidence(
    store::InMemoryEvidenceStore;
    plan_id = nothing,
    problem_fingerprint = nothing,
    status = nothing,
)
    return filter(store.records) do evidence
        (isnothing(plan_id) || evidence.plan_id == plan_id) &&
            (
                isnothing(problem_fingerprint) ||
                evidence.problem_fingerprint == problem_fingerprint
            ) &&
            (isnothing(status) || evidence.status == status)
    end
end

@testitem "Evidence remains linked to source bundles" default_imports=false begin
    using MetaStrategist
    using Test

    reference = EvidenceReference(
        "perfchecker-run-bundle/1",
        "perf/results/run-1";
        digest = "sha256:abc",
    )
    evidence = RunEvidence(
        :cbls_graph,
        "instance-a",
        :budget_exhausted;
        metrics = Dict(:iterations => 128, :best_violation => 2),
        references = [reference],
        context = Dict(:seed => 42),
    )
    store = InMemoryEvidenceStore()
    @test append_evidence!(store, evidence) === evidence
    @test query_evidence(store; plan_id = :cbls_graph) == [evidence]
    @test isempty(query_evidence(store; status = :success))
    @test only(evidence.references) === reference
    @test_throws ArgumentError RunEvidence(
        :bad,
        "instance-a",
        :failed;
        metrics = Dict(:time => Inf),
    )
end
