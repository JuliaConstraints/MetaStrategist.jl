module PreparationScenarios
using MetaStrategist
const MS=MetaStrategist

struct AddPhase
    amount::Int
end
(phase::AddPhase)(value)=(value[]+=phase.amount;nothing)
phase_factory(parameters,context)=AddPhase(parameters.amount)

function template(count)
    catalog=MS.PhaseCatalog();defaults=Dict{Symbol,MS.PhaseChoice}()
    for index in 1:count
        role=Symbol(:phase,index)
        dependencies=index==1 ? () : (Symbol(:phase,index-1),)
        MS.register_phase!(catalog,MS.PhaseDefinition(role,:add,phase_factory;
            dependencies,reads=(:value,),writes=(:value,)))
        defaults[role]=MS.PhaseChoice(:add;amount=index)
    end
    profile=MS.StrategyProfile(:preparation,"1",defaults)
    MS.strategy_template(MS.resolve_strategy(catalog,profile;
        roots=(Symbol(:phase,count),),inputs=(:value,)))
end

function reference_case(parameters)
    count=get(parameters,"phases",64);repetitions=get(parameters,"repetitions",32)
    prepare=()->(;template=template(count),budget=MS.GenerationBudget(),value=Ref(0))
    operation=fixture->begin
        fixture.value[]=0
        before=MS.preparation_statistics(fixture.budget).preparations
        prepared=nothing
        for _ in 1:repetitions
            prepared=MS.instantiate_strategy(fixture.template;budget=fixture.budget,mode=:reference)
            MS.execute!(prepared.kernel,fixture.value)
        end
        (;prepared,preparations=MS.preparation_statistics(fixture.budget).preparations-before)
    end
    verify=(fixture,result)->result.preparations==repetitions &&
        result.prepared.mode==:reference && length(result.prepared.kernel.phases)==count &&
        fixture.value[]==repetitions*sum(1:count) &&
        MS.preparation_statistics(fixture.budget).variants==0 &&
        MS.preparation_statistics(fixture.budget).fallbacks==0
    (;prepare,operation,verify)
end
end
reference_preparation_case(p)=PreparationScenarios.reference_case(p)
