module CapabilityFilteringTests
using Test, MetaStrategist
const MS=MetaStrategist
capabilities(mask)=Tuple(c for (bit,c) in enumerate((:cpu,:discrete))
    if !iszero(mask & (1<<(bit-1))))

@testset "Capability filtering agrees with exhaustive bitmask truth" begin
    guides=[(required,forbidden,MS.UserGuidance(required=capabilities(required),
        forbidden=capabilities(forbidden))) for required in 0:3 for forbidden in 0:3
        if iszero(required & forbidden)]
    for features in 0:3,solver_provides in 0:3,resource_provides in 0:3,
            solver_requires in 0:3,resource_requires in 0:3
        problem=MS.ProblemDescriptor("exhaustive";features=capabilities(features))
        solver=MS.SolverCapability(:solver,v"1";provides=capabilities(solver_provides),
            requires=capabilities(solver_requires))
        resource=MS.ResourceSpec(:resource,:cpu;provides=capabilities(resource_provides),
            requires=capabilities(resource_requires))
        requirements=iszero(solver_requires & ~(features | resource_provides)) &&
            iszero(resource_requires & ~(features | solver_provides))
        available=features | solver_provides | resource_provides
        @test MS._requirements_satisfied(problem,solver,resource)==requirements
        @test MS.compatible(problem,solver,resource)==requirements
        @test MS._available_capabilities(problem,solver,resource)==Set(capabilities(available))
        for (required,forbidden,guide) in guides
            expected=requirements && iszero(required & ~available) && iszero(forbidden & available)
            @test MS.compatible(problem,solver,resource,guide)==expected
        end
    end
end

function reference(problem,solver,resource,guide)
    available=union(problem.features,solver.capabilities.provides,resource.capabilities.provides)
    issubset(solver.capabilities.requires,union(problem.features,resource.capabilities.provides)) &&
        issubset(resource.capabilities.requires,union(problem.features,solver.capabilities.provides)) &&
        issubset(guide.required,available) && isempty(intersect(guide.forbidden,available))
end

@testset "Filtering observes current sets and returns fresh ordered binding lists" begin
    problem=MS.ProblemDescriptor("mutable-inputs")
    solver=MS.SolverCapability(:solver,v"1")
    resource=MS.ResourceSpec(:resource,:cpu;provides=())
    guide=MS.UserGuidance()
    sets=(problem.features,solver.capabilities.provides,resource.capabilities.provides,
        solver.capabilities.requires,resource.capabilities.requires,guide.required,guide.forbidden)
    for set in sets
        push!(set,:external)
        @test MS.compatible(problem,solver,resource,guide)==reference(problem,solver,resource,guide)
        snapshot=map(copy,sets)
        MS.compatible(problem,solver,resource,guide)
        @test sets==snapshot
        delete!(set,:external)
        @test MS.compatible(problem,solver,resource,guide)==reference(problem,solver,resource,guide)
    end
    push!(problem.features,:cpu)
    available=MS._available_capabilities(problem,solver,resource)
    empty!(available)
    @test problem.features==Set((:cpu,))
    @test MS._available_capabilities(problem,solver,resource)==Set((:cpu,))
    other_solver=MS.SolverCapability(:other_solver,v"1")
    other_resource=MS.ResourceSpec(:other_resource,:cpu)
    inventory=MS.ResourceInventory((other_resource,resource))
    solvers=(other_solver,solver,other_solver)
    expected=[MS.CandidateBinding(s.id,r.id) for s in solvers for r in inventory]
    first=MS.eligible_bindings(problem,inventory,solvers,guide)
    second=MS.eligible_bindings(problem,inventory,solvers,guide)
    @test first==expected
    @test second==expected
    @test first!==second
    empty!(first)
    @test second==expected
    @test MS.eligible_bindings(problem,inventory,solvers,guide)==expected
end
end
