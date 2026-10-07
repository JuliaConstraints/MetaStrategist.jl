"""Capabilities offered and required by one resource or solver."""
struct CapabilityProfile
    provides::Set{Symbol}
    requires::Set{Symbol}
    attributes::Dict{Symbol,Any}
end

function CapabilityProfile(; provides = (), requires = (), attributes = Dict{Symbol,Any}())
    return CapabilityProfile(
        Set{Symbol}(Symbol.(provides)),
        Set{Symbol}(Symbol.(requires)),
        Dict{Symbol,Any}(Symbol(key) => value for (key, value) in pairs(attributes)),
    )
end

"""One schedulable hardware or remote-execution resource."""
struct ResourceSpec
    id::Symbol
    kind::Symbol
    capacity::Int
    capabilities::CapabilityProfile

    function ResourceSpec(
        id::Symbol,
        kind::Symbol,
        capacity::Integer,
        capabilities::CapabilityProfile,
    )
        isempty(string(id)) && throw(ArgumentError("a resource id cannot be empty"))
        capacity > 0 || throw(ArgumentError("resource capacity must be strictly positive"))
        return new(id, kind, Int(capacity), capabilities)
    end
end

function ResourceSpec(
    id::Symbol,
    kind::Symbol;
    capacity::Integer = 1,
    provides = (kind,),
    requires = (),
    attributes = Dict{Symbol,Any}(),
)
    profile = CapabilityProfile(; provides, requires, attributes)
    return ResourceSpec(id, kind, capacity, profile)
end

"""A validated, indexed collection of resources available to MetaStrategist."""
struct ResourceInventory
    resources::Vector{ResourceSpec}
    positions::Dict{Symbol,Int}

    function ResourceInventory(resources)
        collected = ResourceSpec[resources...]
        positions = Dict{Symbol,Int}()
        for (index, resource) in pairs(collected)
            haskey(positions, resource.id) &&
                throw(ArgumentError("duplicate resource id: $(resource.id)"))
            positions[resource.id] = index
        end
        return new(collected, positions)
    end
end

ResourceInventory() = ResourceInventory(ResourceSpec[])
Base.length(inventory::ResourceInventory) = length(inventory.resources)
Base.isempty(inventory::ResourceInventory) = isempty(inventory.resources)
Base.iterate(inventory::ResourceInventory, state...) =
    iterate(inventory.resources, state...)
Base.getindex(inventory::ResourceInventory, id::Symbol) =
    inventory.resources[inventory.positions[id]]

"""Pre-solve features and identity of one problem instance."""
struct ProblemDescriptor
    fingerprint::String
    features::Set{Symbol}
    attributes::Dict{Symbol,Any}

    function ProblemDescriptor(
        fingerprint::AbstractString;
        features = (),
        attributes = Dict{Symbol,Any}(),
    )
        isempty(fingerprint) &&
            throw(ArgumentError("a problem fingerprint cannot be empty"))
        return new(
            String(fingerprint),
            Set{Symbol}(Symbol.(features)),
            Dict{Symbol,Any}(Symbol(key) => value for (key, value) in pairs(attributes)),
        )
    end
end

"""Static capabilities and resource requirements of one solver implementation."""
struct SolverCapability
    id::Symbol
    version::VersionNumber
    capabilities::CapabilityProfile
end

function SolverCapability(
    id::Symbol,
    version::VersionNumber;
    provides = (),
    requires = (),
    attributes = Dict{Symbol,Any}(),
)
    isempty(string(id)) && throw(ArgumentError("a solver id cannot be empty"))
    return SolverCapability(
        id,
        version,
        CapabilityProfile(; provides, requires, attributes),
    )
end

"""A validated, indexed collection of solver capabilities."""
struct SolverCatalog
    solvers::Vector{SolverCapability}
    positions::Dict{Symbol,Int}

    function SolverCatalog(solvers)
        collected = SolverCapability[solvers...]
        positions = Dict{Symbol,Int}()
        for (index, solver) in pairs(collected)
            haskey(positions, solver.id) &&
                throw(ArgumentError("duplicate solver id: $(solver.id)"))
            positions[solver.id] = index
        end
        return new(collected, positions)
    end
end

SolverCatalog() = SolverCatalog(SolverCapability[])
Base.length(catalog::SolverCatalog) = length(catalog.solvers)
Base.isempty(catalog::SolverCatalog) = isempty(catalog.solvers)
Base.iterate(catalog::SolverCatalog, state...) = iterate(catalog.solvers, state...)
Base.getindex(catalog::SolverCatalog, id::Symbol) = catalog.solvers[catalog.positions[id]]

"""One solver/resource pair retained by capability filtering."""
struct CandidateBinding
    solver::Symbol
    resource::Symbol
end

function _available_capabilities(
    problem::ProblemDescriptor,
    solver::SolverCapability,
    resource::ResourceSpec,
)
    return union(
        problem.features,
        solver.capabilities.provides,
        resource.capabilities.provides,
    )
end

function _requirements_satisfied(
    problem::ProblemDescriptor,
    solver::SolverCapability,
    resource::ResourceSpec,
)
    available = union(problem.features, resource.capabilities.provides)
    resource_environment = union(problem.features, solver.capabilities.provides)
    return issubset(solver.capabilities.requires, available) &&
           issubset(resource.capabilities.requires, resource_environment)
end

@testitem "Capability inventory" default_imports=false begin
    using MetaStrategist
    using Test

    cpu = ResourceSpec(:cpu0, :cpu; capacity = 8, provides = (:cpu, :threads))
    gpu = ResourceSpec(:gpu0, :gpu; provides = (:gpu, :float32))
    inventory = ResourceInventory((cpu, gpu))
    @test length(inventory) == 2
    @test inventory[:gpu0] === gpu
    @test_throws ArgumentError ResourceInventory((cpu, cpu))
    @test_throws ArgumentError ResourceSpec(:invalid, :cpu; capacity = 0)

    problem = ProblemDescriptor("sha256:example"; features = (:discrete, :csp))
    cbls = SolverCapability(
        :cbls,
        v"0.4.10";
        provides = (:csp, :anytime),
        requires = (:cpu, :discrete),
    )
    catalog = SolverCatalog((cbls,))
    @test catalog[:cbls] === cbls
    @test_throws ArgumentError SolverCatalog((cbls, cbls))
    @test MetaStrategist._requirements_satisfied(problem, cbls, cpu)
    @test !MetaStrategist._requirements_satisfied(problem, cbls, gpu)
end
