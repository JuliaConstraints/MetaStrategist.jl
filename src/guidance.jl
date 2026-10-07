"""Finite, non-negative limits. Missing keys mean that no limit was declared."""
struct Budget
    limits::Dict{Symbol,Float64}

    function Budget(limits)
        normalized = Dict{Symbol,Float64}()
        for (key, raw_value) in pairs(limits)
            value = Float64(raw_value)
            isfinite(value) && value >= 0 ||
                throw(ArgumentError("budget limits must be finite and non-negative"))
            normalized[Symbol(key)] = value
        end
        return new(normalized)
    end
end

Budget(; limits...) = Budget(limits)
Base.getindex(budget::Budget, key::Symbol) = budget.limits[key]
Base.get(budget::Budget, key::Symbol, default) = get(budget.limits, key, default)
Base.isempty(budget::Budget) = isempty(budget.limits)

"""Hard capability constraints, soft preferences and the total user budget."""
struct UserGuidance
    required::Set{Symbol}
    forbidden::Set{Symbol}
    preferences::Dict{Symbol,Float64}
    budget::Budget

    function UserGuidance(required, forbidden, preferences, budget::Budget)
        required_set = Set{Symbol}(Symbol.(required))
        forbidden_set = Set{Symbol}(Symbol.(forbidden))
        conflict = intersect(required_set, forbidden_set)
        isempty(conflict) ||
            throw(ArgumentError("guidance both requires and forbids: $(collect(conflict))"))
        weights = Dict{Symbol,Float64}()
        for (key, raw_value) in pairs(preferences)
            value = Float64(raw_value)
            isfinite(value) || throw(ArgumentError("preference weights must be finite"))
            weights[Symbol(key)] = value
        end
        return new(required_set, forbidden_set, weights, budget)
    end
end

function UserGuidance(;
    required = (),
    forbidden = (),
    preferences = Dict{Symbol,Float64}(),
    budget = Budget(),
)
    return UserGuidance(required, forbidden, preferences, budget)
end

"""Return whether one solver/resource binding satisfies problem and user capabilities."""
function compatible(
    problem::ProblemDescriptor,
    solver::SolverCapability,
    resource::ResourceSpec,
    guidance::UserGuidance = UserGuidance(),
)
    _requirements_satisfied(problem, solver, resource) || return false
    available = _available_capabilities(problem, solver, resource)
    return issubset(guidance.required, available) &&
           isempty(intersect(guidance.forbidden, available))
end

"""Enumerate compatible solver/resource pairs without ranking or hidden learning."""
function eligible_bindings(
    problem::ProblemDescriptor,
    inventory::ResourceInventory,
    solvers,
    guidance::UserGuidance = UserGuidance(),
)
    bindings = CandidateBinding[]
    for solver in solvers, resource in inventory
        compatible(problem, solver, resource, guidance) || continue
        push!(bindings, CandidateBinding(solver.id, resource.id))
    end
    return bindings
end

@testitem "Transparent capability filtering" default_imports=false begin
    using MetaStrategist
    using Test

    inventory = ResourceInventory((
        ResourceSpec(:cpu0, :cpu; provides = (:cpu, :threads)),
        ResourceSpec(:gpu0, :gpu; provides = (:gpu, :float32)),
    ))
    problem = ProblemDescriptor("instance-a"; features = (:discrete, :csp))
    solvers = SolverCatalog((
        SolverCapability(
            :cbls,
            v"0.4.10";
            provides = (:anytime,),
            requires = (:cpu, :discrete),
        ),
        SolverCapability(
            :gpu_search,
            v"1.0.0";
            provides = (:anytime,),
            requires = (:gpu, :discrete),
        ),
    ))

    @test Set(eligible_bindings(problem, inventory, solvers)) ==
          Set((CandidateBinding(:cbls, :cpu0), CandidateBinding(:gpu_search, :gpu0)))
    cpu_only = UserGuidance(required = (:cpu,), budget = Budget(iterations = 128))
    @test eligible_bindings(problem, inventory, solvers, cpu_only) ==
          [CandidateBinding(:cbls, :cpu0)]
    @test cpu_only.budget[:iterations] == 128.0
    @test_throws ArgumentError UserGuidance(required = (:gpu,), forbidden = (:gpu,))
    @test_throws ArgumentError Budget(seconds = Inf)
end
