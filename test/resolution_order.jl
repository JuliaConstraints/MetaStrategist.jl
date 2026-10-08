module ResolutionOrderTests
using Test, MetaStrategist
const MS = MetaStrategist
struct NoOpPhase end
(::NoOpPhase)(context) = nothing
phase_factory(parameters, context) = NoOpPhase()

# Enumerating all valid permutations supplies a graph oracle independently of
# the resolver's readiness queue. Longest-path depth fixes the original batches.
const PERMUTATIONS = [order for order in Iterators.product(1:4,1:4,1:4,1:4)
    if length(Set(order)) == 4]
function expected_order(edges, roles)
    valid = findfirst(PERMUTATIONS) do order
        positions = [findfirst(==(role),order) for role in 1:4]
        all(positions[source] < positions[target] for (source,target) in edges)
    end
    valid === nothing && return nothing
    depth = zeros(Int,4)
    for target in PERMUTATIONS[valid]
        depth[target] = 1+maximum((depth[source] for (source,destination) in edges
            if destination == target); init=0)
    end
    roles[sortperm(1:4; by=index->(depth[index],string(roles[index])))]
end

@testset "All four-phase graphs retain batch order, identity and cycle rejection" begin
    roles = [:z,:a,:β,Symbol("é")]
    possible_edges = [(source,target) for source in 1:4 for target in 1:4 if source != target]
    defaults = Dict(role=>MS.PhaseChoice(:noop; amount=index) for (index,role) in pairs(roles))
    profile = MS.StrategyProfile(:order,"1",defaults)
    for mask in 0:(1<<length(possible_edges))-1
        edges = [edge for (bit,edge) in pairs(possible_edges) if mask & (1<<(bit-1)) != 0]
        expected = expected_order(edges,roles)
        catalog = MS.PhaseCatalog()
        for target in 1:4
            predecessors = Tuple(roles[source] for (source,destination) in edges if destination == target)
            MS.register_phase!(catalog,MS.PhaseDefinition(roles[target],:noop,phase_factory;
                after=predecessors))
        end
        if expected === nothing
            exception = try
                MS.resolve_strategy(catalog,profile; roots=roles)
                nothing
            catch caught
                caught
            end
            @test exception isa ArgumentError
            @test occursin("phase ordering cycle among",sprint(showerror,exception))
        else
            resolved = MS.resolve_strategy(catalog,profile; roots=roles)
            @test [phase.definition.category for phase in resolved.phases] == expected
            reversed = MS.resolve_strategy(catalog,profile; roots=reverse(roles))
            @test MS.strategy_snapshot(reversed) == MS.strategy_snapshot(resolved)
            @test reversed.shape_key == resolved.shape_key
        end
    end
end

@testset "Dependency and before/after duplicates count as one ordering edge" begin
    catalog = MS.PhaseCatalog()
    MS.register_phase!(catalog,MS.PhaseDefinition(:a,:noop,phase_factory; before=(:b,:b)))
    MS.register_phase!(catalog,MS.PhaseDefinition(:b,:noop,phase_factory;
        dependencies=(:a,:a),after=(:a,:a)))
    profile = MS.StrategyProfile(:duplicates,"1",Dict(role=>MS.PhaseChoice(:noop) for role in (:a,:b)))
    resolved = MS.resolve_strategy(catalog,profile; roots=(:b,))
    @test [phase.definition.category for phase in resolved.phases] == [:a,:b]
    @test length(resolved.phases) == 2
end
end
