const STRATEGY_PLAN_SCHEMA = "julia-constraints-strategy-plan/1"

"""One factor of a strategy plan; parameters stay concrete after plan sealing."""
struct StrategyComponent{P<:NamedTuple}
    role::Symbol
    implementation::Symbol
    parameters::P
    requires::Set{Symbol}
    provides::Set{Symbol}
end

function StrategyComponent(
    role::Symbol,
    implementation::Symbol;
    requires = (),
    provides = (),
    parameters...,
)
    return StrategyComponent(
        role,
        implementation,
        (; parameters...),
        Set{Symbol}(Symbol.(requires)),
        Set{Symbol}(Symbol.(provides)),
    )
end

"""A model-specific, factorized plan selected outside solver hot loops."""
struct StrategyPlan{C<:Tuple}
    schema::String
    id::Symbol
    problem_fingerprint::String
    solver::Symbol
    resources::Vector{Symbol}
    components::C
    budget::Budget
    metadata::Dict{Symbol,Any}
end

function StrategyPlan(
    id::Symbol,
    problem::ProblemDescriptor,
    solver::Symbol,
    components::Tuple;
    resources = (),
    budget = Budget(),
    metadata = Dict{Symbol,Any}(),
)
    isempty(components) &&
        throw(ArgumentError("a strategy plan needs at least one component"))
    resource_ids = Symbol.(collect(resources))
    length(unique(resource_ids)) == length(resource_ids) ||
        throw(ArgumentError("a strategy plan cannot bind a resource twice"))
    return StrategyPlan(
        STRATEGY_PLAN_SCHEMA,
        id,
        problem.fingerprint,
        solver,
        resource_ids,
        components,
        budget,
        Dict{Symbol,Any}(Symbol(key) => value for (key, value) in pairs(metadata)),
    )
end

"""
The sealed boundary handed to an execution adapter. Only the selected units are part of its
concrete type; the complete strategy catalog remains outside the solver hot path.
"""
struct CompiledExecutionPlan{P<:StrategyPlan,U<:Tuple,C,T}
    source::P
    units::U
    controller::C
    telemetry::T
end

function CompiledExecutionPlan(
    source::StrategyPlan,
    units::Tuple;
    controller = nothing,
    telemetry = nothing,
)
    isempty(units) &&
        throw(ArgumentError("a compiled plan needs at least one execution unit"))
    return CompiledExecutionPlan(source, units, controller, telemetry)
end

"""Return the concrete tuple of active units in a sealed execution plan."""
execution_units(plan::CompiledExecutionPlan) = plan.units

@testitem "Factorized and sealed strategy plans" default_imports=false begin
    using MetaStrategist
    using Test

    problem = ProblemDescriptor("instance-a"; features = (:discrete,))
    selection = StrategyComponent(:selection, :worst_variable; ties = :random)
    neighborhood = StrategyComponent(
        :neighborhood,
        :constraint_graph;
        depth = 3,
        provides = (:batch_moves,),
    )
    plan = StrategyPlan(
        :cbls_graph,
        problem,
        :cbls,
        (selection, neighborhood);
        resources = (:cpu0,),
        budget = Budget(iterations = 128),
    )
    @test plan.schema == MetaStrategist.STRATEGY_PLAN_SCHEMA
    @test plan.components isa Tuple{typeof(selection),typeof(neighborhood)}
    @test plan.components[2].parameters.depth == 3

    unit = (solver = :cbls, state = :owned)
    compiled = CompiledExecutionPlan(plan, (unit,); controller = :sequential)
    @test execution_units(compiled) === compiled.units
    @test only(execution_units(compiled)) === unit
    @test_throws ArgumentError StrategyPlan(:empty, problem, :cbls, ())
    @test_throws ArgumentError CompiledExecutionPlan(plan, ())
end
