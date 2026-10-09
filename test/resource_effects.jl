module ResourceEffectTests
using Test, MetaStrategist
const MS = MetaStrategist
const RESOURCES = (:first_resource,:second_resource)
resources(mask) = Tuple(RESOURCES[bit] for bit in 1:2 if mask & (1<<(bit-1)) != 0)

@testset "Every two-resource effect combination preserves ordering and lifetime" begin
    factory_calls = Ref(0)
    factory = (parameters,context) -> (factory_calls[]+=1)
    profile = MS.StrategyProfile(:effects,"1",Dict(role=>MS.PhaseChoice(:test) for role in (:a,:b)))
    for ar in 0:3, aw in 0:3, ai in 0:3, br in 0:3, bw in 0:3, bi in 0:3,
            ordering in (:independent,:a_first,:b_first)
        masks = Dict(:a=>(ar,aw,ai), :b=>(br,bw,bi))
        catalog = MS.PhaseCatalog()
        for role in (:a,:b)
            reads,writes,invalidates = masks[role]
            after = ordering==:a_first && role==:b ? (:a,) :
                ordering==:b_first && role==:a ? (:b,) : ()
            MS.register_phase!(catalog,MS.PhaseDefinition(role,:test,factory;
                reads=resources(reads),writes=resources(writes),invalidates=resources(invalidates),after))
        end
        conflict = ((aw|ai)&(br|bw|bi))!=0 || ((bw|bi)&ar)!=0
        order = ordering==:b_first ? (:b,:a) : (:a,:b)
        expected = conflict && ordering==:independent ? "unordered resource effects between a and b" : nothing
        available = 3
        if expected===nothing
            for role in order
                reads,writes,invalidates = masks[role]
                if reads & ~available != 0
                    expected = "missing/invalid resources for $role:"
                    break
                end
                available = (available & ~invalidates)|writes
            end
        end
        result = try
            MS.resolve_strategy(catalog,profile;roots=(:b,:a),inputs=RESOURCES)
        catch exception
            exception
        end
        if expected===nothing
            @test result isa MS.ExecutionIR
            @test Tuple(p.definition.category for p in result.phases)==order
            @test result.inputs==Tuple(sort(collect(RESOURCES);by=string))
            @test all(p->p.definition===catalog.definitions[(p.definition.category,:test,"1")],result.phases)
        else
            @test result isa ArgumentError
            @test occursin(expected,sprint(showerror,result))
        end
    end
    @test factory_calls[]==0
end

@testset "Capabilities, ownership and exact failure context remain explicit" begin
    factory = (parameters,context) -> nothing
    profile = MS.StrategyProfile(:requirements,"1",Dict(role=>MS.PhaseChoice(:test) for role in (:a,:b)))
    for required in 0:3, supplied in 0:3, provided in 0:3
        catalog = MS.PhaseCatalog()
        MS.register_phase!(catalog,MS.PhaseDefinition(:a,:test,factory;provides=resources(provided)))
        MS.register_phase!(catalog,MS.PhaseDefinition(:b,:test,factory;
            dependencies=(:a,),requires=resources(required)))
        expected = required & ~(supplied|provided)==0
        result = try
            MS.resolve_strategy(catalog,profile;roots=(:b,),capabilities=resources(supplied))
        catch exception
            exception
        end
        @test (result isa MS.ExecutionIR)==expected
        if expected
            @test result.capabilities==Tuple(sort(collect(resources(supplied));by=string))
        else
            @test result isa ArgumentError
            @test occursin("missing capabilities for b:",sprint(showerror,result))
        end
    end
    catalog = MS.PhaseCatalog()
    for role in (:a,:b)
        MS.register_phase!(catalog,MS.PhaseDefinition(role,:test,factory;owns=(:shared,)))
    end
    result = try MS.resolve_strategy(catalog,profile;roots=(:b,:a)) catch exception; exception end
    @test result isa ArgumentError
    @test sprint(showerror,result)=="ArgumentError: resource shared owned by a and b"
end
end
