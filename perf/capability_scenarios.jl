module CapabilityScenarios
using MetaStrategist
const MS=MetaStrategist

function description()
    problem=MS.ProblemDescriptor("portable-fixture";features=(:discrete,:csp))
    resources=MS.ResourceInventory(ntuple(i->MS.ResourceSpec(Symbol(:resource_,i),
        iseven(i) ? :cpu : :gpu;
        provides=iseven(i) ? (:cpu,:threads) : (:gpu,:float32),
        requires=i%3==0 ? (:anytime,) : ()),16))
    solvers=MS.SolverCatalog(ntuple(i->MS.SolverCapability(Symbol(:solver_,i),v"1";
        provides=i%3==0 ? (:anytime,:async) : (:anytime,),
        requires=iseven(i) ? (:cpu,:discrete) : (:gpu,:discrete)),16))
    guides=(MS.UserGuidance(),MS.UserGuidance(required=(:cpu,:anytime),forbidden=(:gpu,)),
        MS.UserGuidance(required=(:async,)),MS.UserGuidance(forbidden=(:threads,)))
    # This oracle uses fixture ids and their declared rules, independently of
    # MetaStrategist's set representation and compatibility implementation.
    expected=map(eachindex(guides)) do guide
        [(solver=Symbol(:solver_,i),resource=Symbol(:resource_,j))
            for i in 1:16 for j in 1:16 if iseven(i)==iseven(j) &&
                (guide==1 || guide==2 && iseven(j) ||
                 guide==3 && i%3==0 || guide==4 && isodd(j))]
    end
    (;problem,resources,solvers,guides,expected)
end

function compatibility_case(parameters)
    repetitions=get(parameters,"repetitions",32)
    prepare=description
    operation=fixture->begin
        accepted=0
        for _ in 1:repetitions,solver in fixture.solvers,
                resource in fixture.resources,guide in fixture.guides
            accepted+=MS.compatible(fixture.problem,solver,resource,guide)
        end
        accepted
    end
    verify=(fixture,result)->result==repetitions*sum(length,fixture.expected)
    (;prepare,operation,verify)
end

function bindings_case(parameters)
    repetitions=get(parameters,"repetitions",32)
    prepare=description
    operation=fixture->begin
        result=nothing
        for _ in 1:repetitions
            result=map(fixture.guides) do guide
                MS.eligible_bindings(fixture.problem,fixture.resources,fixture.solvers,guide)
            end
        end
        result
    end
    verify=(fixture,result)->length(result)==length(fixture.expected) &&
        all(zip(result,fixture.expected)) do (actual,expected)
            [(;solver=b.solver,resource=b.resource) for b in actual]==expected
        end
    (;prepare,operation,verify)
end
end
compatibility_case(p)=CapabilityScenarios.compatibility_case(p)
bindings_case(p)=CapabilityScenarios.bindings_case(p)
