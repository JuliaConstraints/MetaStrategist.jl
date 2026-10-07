using MetaStrategist
@testset "Preparation service and receipt persistence" begin
    b=GenerationBudget(max_variants=1)
    @test deepcopy(b)===b
    @test default_preparation_service()===default_preparation_service()
    c=PhaseCatalog()
    register_phase!(c,PhaseDefinition(:a,:add,(p,c)->(f->(f[]+=p.amount));writes=(:x,)))
    p=StrategyProfile(:test,"1",Dict(:a=>PhaseChoice(:add;amount=1)))
    ir=resolve_strategy(c,p;roots=(:a,))
    k=prepare_strategy(ir;budget=b,mode=:typed)
    f=Ref(0);execute!(k.kernel,f)
    @test f[]==1 && k.mode==:typed
    @test preparation_statistics(b).variants==1
    @test prepare_strategy(ir;budget=b).mode==:reference
    @test preparation_statistics(b).recycle_requested
    r=preparation_receipt(unit="unit-1",component=(;key=ir.semantic_key),
        execution=(;mode=:typed),model_revision=UInt64(2))
    mktempdir() do dir
        path=joinpath(dir,"r.toml")
        write_preparation_receipt(path,r)
        @test MetaStrategist.canonical_value(read_preparation_receipt(path))==
            MetaStrategist.canonical_value(receipt_snapshot(r))
        @test_throws ArgumentError write_preparation_receipt(path,r)
        text=read(path,String)
        write(path,replace(text,r.identity=>repeat("0",64)))
        @test_throws ArgumentError read_preparation_receipt(path)
    end
end

@testset "Effect ordering agrees with independent transitive closure" begin
    for n in (2,4,8,16), variant in 1:12
        edges=falses(n,n)
        for i in 1:n, j in i+1:n
            edges[i,j]=iszero(mod(11i+7j+variant,5)) || (iseven(variant) && j==i+1)
        end
        closure=copy(edges)
        for k in 1:n, i in 1:n, j in 1:n
            closure[i,j] |= closure[i,k] && closure[k,j]
        end
        ordered=all(closure[i,j] || closure[j,i] for i in 1:n for j in i+1:n)
        catalog=PhaseCatalog();defaults=Dict{Symbol,PhaseChoice}()
        for i in 1:n
            role=Symbol("p",i)
            register_phase!(catalog,PhaseDefinition(role,:test,(p,c)->identity;
                dependencies=Tuple(Symbol("p",j) for j in 1:n if edges[j,i]),
                reads=(:shared,),writes=(:shared,)))
            defaults[role]=PhaseChoice(:test)
        end
        profile=StrategyProfile(:dag,"1",defaults)
        if ordered
            ir=resolve_strategy(catalog,profile;roots=Tuple(keys(defaults)),inputs=(:shared,))
            @test length(ir.phases)==n
            @test [p.definition.category for p in ir.phases]==[Symbol("p",i) for i in 1:n]
        else
            @test_throws ArgumentError resolve_strategy(catalog,profile;roots=Tuple(keys(defaults)),inputs=(:shared,))
        end
    end
end
