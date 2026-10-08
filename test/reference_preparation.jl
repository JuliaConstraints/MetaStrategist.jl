module ReferencePreparationTests
using Test, MetaStrategist
const MS=MetaStrategist
include("../perf/preparation_scenarios.jl")

mutable struct CapturedPhase
    private::Base.RefValue{Int}
    shared::Base.RefValue{Int}
end
(phase::CapturedPhase)(value)=(phase.private[]+=1;value[]+=phase.shared[];nothing)
function capture_factory(parameters,context)
    phase=CapturedPhase(Ref(0),context.shared)
    push!(context.created,phase)
    phase
end
function capture_template()
    catalog=MS.PhaseCatalog()
    MS.register_phase!(catalog,MS.PhaseDefinition(:left,:capture,capture_factory;
        reads=(:value,),writes=(:value,)))
    MS.register_phase!(catalog,MS.PhaseDefinition(:right,:capture,capture_factory;
        dependencies=(:left,),reads=(:value,),writes=(:value,)))
    profile=MS.StrategyProfile(:capture,"1",Dict(:left=>MS.PhaseChoice(:capture),
        :right=>MS.PhaseChoice(:capture)))
    MS.strategy_template(MS.resolve_strategy(catalog,profile;roots=(:right,),inputs=(:value,)))
end

@testset "Reference preparation owns fresh containers and preserves phase graphs" begin
    template=capture_template()
    context=(;shared=Ref(3),created=CapturedPhase[])
    budget=MS.GenerationBudget()
    first=MS.instantiate_strategy(template,context;budget,mode=:reference)
    second=MS.instantiate_strategy(template,context;budget,mode=:reference)
    @test first.kernel.phases!==second.kernel.phases
    @test first.kernel.phases[1]===context.created[1]
    @test first.kernel.phases[2]===context.created[2]
    @test second.kernel.phases[1]===context.created[3]
    @test first.kernel.phases[1].private!==second.kernel.phases[1].private
    @test first.kernel.phases[1].shared===first.kernel.phases[2].shared===context.shared
    value=Ref(0);MS.execute!(first.kernel,value)
    @test value[]==6 && all(p->p.private[]==1,first.kernel.phases)
    @test all(p->p.private[]==0,second.kernel.phases)
    cloned=MS.clone_kernel(first.kernel)
    @test cloned.phases!==first.kernel.phases
    @test cloned.phases[1].shared===cloned.phases[2].shared
    @test cloned.phases[1].shared!==context.shared
    empty!(second.kernel.phases)
    @test length(first.kernel.phases)==2 && length(template.factories)==2
    statistics=MS.preparation_statistics(budget)
    @test statistics.preparations==2 && statistics.variants==0 && statistics.fallbacks==0
end

@testset "Reference factory path and typed-tuple quota fallback agree" begin
    template=capture_template();context=(;shared=Ref(4),created=CapturedPhase[])
    budget=MS.GenerationBudget(max_variants=1)
    typed=MS.instantiate_strategy(template,context;budget,mode=:typed)
    fallback=MS.instantiate_strategy(template,context;budget,mode=:generated)
    @test typed.mode==:typed && fallback.mode==:reference
    @test fallback.kernel.phases[1]===context.created[3]
    @test fallback.kernel.phases[2]===context.created[4]
    @test fallback.kernel.phases[1].shared===fallback.kernel.phases[2].shared===context.shared
    value=Ref(0);MS.execute!(fallback.kernel,value)
    @test value[]==8
    statistics=MS.preparation_statistics(budget)
    @test statistics.preparations==2 && statistics.variants==1 && statistics.fallbacks==1
    @test statistics.recycle_requested
    for count in (3,64,129)
        case=PreparationScenarios.reference_case(Dict("phases"=>count))
        fixture=case.prepare();result=case.operation(fixture)
        @test case.verify(fixture,result)
        @test result.prepared.kernel.phases isa Vector{Any}
    end
    large=PreparationScenarios.template(129)
    prepared=MS.instantiate_strategy(large;mode=:generated,budget=MS.GenerationBudget())
    @test prepared.mode==:reference && length(prepared.kernel.phases)==129
end
end
