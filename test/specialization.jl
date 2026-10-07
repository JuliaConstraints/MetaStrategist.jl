using Test, MetaStrategist
const MS = MetaStrategist
struct AddPhase{T}
    n::T
end
(a::AddPhase)(r) = (r[]+=a.n; nothing)

@testset "Resolved strategy contracts" begin
    c=PhaseCatalog()
    register_phase!(c,PhaseDefinition(:a,:add,(p,ctx)->AddPhase(p.n);reads=(:x,),writes=(:x,)))
    register_phase!(c,PhaseDefinition(:b,:add,(p,ctx)->AddPhase(p.n);dependencies=(:a,),reads=(:x,),writes=(:x,)))
    profile=StrategyProfile(:test,"1",Dict(:a=>PhaseChoice(:add;n=2),:b=>PhaseChoice(:add;n=3)))
    ir=resolve_strategy(c,profile;roots=(:b,),inputs=(:x,))
    @test [p.definition.category for p in ir.phases]==[:a,:b]
    @test restore_strategy(c,strategy_snapshot(ir)).semantic_key==ir.semantic_key
    mktempdir() do dir
        file=joinpath(dir,"checkpoint.toml")
        write_strategy_snapshot(file,ir)
        @test read_strategy_snapshot(file,c).semantic_key==ir.semantic_key
        @test_throws ArgumentError write_strategy_snapshot(file,ir)
    end
    quota=GenerationBudget(max_variants=1)
    prepared=prepare_strategy(ir;budget=quota)
    @test prepared.mode==:generated
    for mode in (:reference,:generated)
        k=prepare_strategy(ir;mode).kernel
        value=Ref(0); execute!(k,value)
        @test value[]==5
        @test @inferred(execute!(k,Ref(0)))===nothing
    end
    for i in 1:2356
        register_phase!(c,PhaseDefinition(Symbol(:unused,i),:add,(p,ctx)->AddPhase(1)))
    end
    same=resolve_strategy(c,profile;roots=(:b,),inputs=(:x,))
    @test same.semantic_key==ir.semantic_key
    @test typeof(prepare_strategy(same).kernel)==typeof(prepared.kernel)
    changed=resolve_strategy(c,profile;roots=(:b,),inputs=(:x,),overrides=(:a=>PhaseChoice(:add;n=4),))
    @test changed.semantic_key!=ir.semantic_key
    @test changed.shape_key==ir.shape_key
    @test prepare_strategy(changed;budget=quota).mode==:generated
    another=resolve_strategy(c,profile;roots=(:b,),inputs=(:x,),overrides=(:a=>PhaseChoice(:add;n=4.0),))
    @test prepare_strategy(another;budget=quota).mode==:reference
    @test quota.recycle_requested
    @test length(quota.variants)==1
    @test prepare_strategy(ir;budget=GenerationBudget(max_phases=1)).mode==:reference
    @test_throws ArgumentError resolve_strategy(c,profile;roots=(:b,),inputs=(:x,),overrides=(:a=>SuppressPhase(),))
    @test_throws ArgumentError resolve_strategy(c,profile;roots=(:b,),overrides=(:a=>PhaseChoice(:add),:a=>PhaseChoice(:add)))
    @test_throws ArgumentError resolve_strategy(c,profile;roots=(:b,))
    @test_throws ArgumentError PhaseChoice(:add;n=[1,2])
    @test_throws ArgumentError PhaseChoice(:path;name="C:/absolute/source.jl")
    @test PhaseChoice(:add;a=1,b=2).parameters==PhaseChoice(:add;b=2,a=1).parameters
    @test restore_strategy(c,strategy_snapshot(ir)).shape_key==ir.shape_key
    template=strategy_template(ir)
    @test typeof(instantiate_strategy(template).kernel)==typeof(prepared.kernel)
    shared=Ref(1)
    graph=(shared,shared)
    cloned=clone_kernel(graph)
    @test cloned[1]===cloned[2] && cloned[1]!==shared
    @test MS.canonical_value((a=1,b=2))==MS.canonical_value((b=2,a=1))
    @test MS.canonical_value(-0.0)!=MS.canonical_value(0.0)
    @test MS.canonical_value(Int32(1))!=MS.canonical_value(Int64(1))
    @test_throws ArgumentError register_phase!(c,first(values(c.definitions)))
    unordered=PhaseCatalog()
    for r in (:a,:b)
        register_phase!(unordered,PhaseDefinition(r,:add,(p,ctx)->AddPhase(1);writes=(:x,)))
    end
    @test_throws ArgumentError resolve_strategy(unordered,profile;roots=(:a,:b))
    cycle=PhaseCatalog()
    register_phase!(cycle,PhaseDefinition(:a,:add,(p,c)->AddPhase(1);dependencies=(:b,)))
    register_phase!(cycle,PhaseDefinition(:b,:add,(p,c)->AddPhase(1);dependencies=(:a,)))
    @test_throws ArgumentError resolve_strategy(cycle,profile;roots=(:b,))
    invalid=PhaseCatalog()
    register_phase!(invalid,PhaseDefinition(:a,:add,(p,c)->AddPhase(1);invalidates=(:x,)))
    register_phase!(invalid,PhaseDefinition(:b,:add,(p,c)->AddPhase(1);dependencies=(:a,),reads=(:x,)))
    @test_throws ArgumentError resolve_strategy(invalid,profile;roots=(:b,),inputs=(:x,))
    caps=PhaseCatalog()
    register_phase!(caps,PhaseDefinition(:a,:add,(p,c)->AddPhase(1);requires=(:integer,)))
    @test_throws ArgumentError resolve_strategy(caps,profile;roots=(:a,))
    @test length(resolve_strategy(caps,profile;roots=(:a,),capabilities=(:integer,)).phases)==1
    pop!(same.phases)
    @test_throws ArgumentError prepare_strategy(same)
end

MetaStrategist.@instrument () function erased_instrument(x)
    MetaStrategist.@telemetry :trace begin
        @deliberately_missing_macro x
    end
    x+1
end
MetaStrategist.@instrument (:trace,) function retained_instrument(x,sink)
    MetaStrategist.@telemetry :trace begin
        MetaStrategist.@telemetry :disabled error("must be removed")
        observe!(sink,:trace;values=x)
    end
    sum(x)
end
@testset "Instrumentation and oracle ownership" begin
    @test erased_instrument(2)==3
    sink=EventBuffer(capacity=1); x=[1,2]
    @test retained_instrument(x,sink)==3
    x[1]=100
    @test only(events(sink)).payload.values==(1,2)
    observe!(sink,:trace)
    @test sink.dropped==1
    @test_throws ArgumentError MS._event_value(Ref(1))
    @test fetch(@async try observe!(sink,:trace); false catch e; e isa ArgumentError end)
    @test_throws ArgumentError MS.instrument_definition(:(()), :(function f(); MetaStrategist.@telemetry :trace return 1; end))
    p=OracleProblem(x->sum(abs2,x),x->all(iszero,x),([-1.0],[1.0]),OracleContract("sphere");valid_domain=x->all(v->-1<=v<=1,x))
    s=OracleSession(p;evaluations=2)
    @test evaluate!(s,[0.5])==0.25
    @test_throws ArgumentError evaluate!(s,[2.0])
    @test s.failures==1 && s.evaluations==2
    @test_throws MS.OracleBudgetExceeded evaluate!(s,[0.0])
    @test oracle_result(s,[0.0]).valid
    @test !oracle_result(s,[0.5]).valid
    adapter=AdapterContract("box","1",(:continuous,),false,false,false)
    @test adapter_decision(p,adapter).allowed
    @test !adapter_decision(p,adapter;require_anytime=true).allowed
    constrained=OracleProblem(identity,identity,nothing,OracleContract("constrained";constraints=true))
    @test !adapter_decision(constrained,adapter).allowed
end

@instrument () function bare_instrument(x)
    @telemetry :trace error("removed")
    x
end
MS.@instrument () function alias_instrument(x)
    MS.@telemetry :trace error("removed")
    x
end
@test bare_instrument(5)==alias_instrument(5)==5
