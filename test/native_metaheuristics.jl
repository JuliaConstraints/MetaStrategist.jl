using Test, MetaStrategist, Metaheuristics
@testset "Native Metaheuristics contract" begin
    bounds=[-ones(2)';ones(2)']
    valid=x->length(x)==2 && all(v->-1<=v<=1,x)
    problem=OracleProblem(x->sum(abs2,x),valid,bounds,OracleContract("sphere/box");valid_domain=valid)
    a=run_metaheuristics(problem;evaluations=17,population=8,iterations=3,seed=42)
    b=run_metaheuristics(problem;evaluations=17,population=8,iterations=3,seed=42)
    @test a.valid && b.valid
    @test a.evaluations==b.evaluations==17
    @test a.solution==b.solution
    @test a.stopped_by==:evaluation_limit
    @test a.observation==:final_only && a.oracle_checks==1
    @test a.adapter.adapter[2]=="3.5.0"
    constrained=OracleProblem(x->(sum(abs2,x),[sum(x)-100.0],[0.0]),valid,bounds,
        OracleContract("sphere/constrained";constraints=true);valid_domain=valid)
    c=run_metaheuristics(constrained;evaluations=16,population=8,iterations=2,seed=12)
    @test c.valid && c.evaluations<=16
    bad=OracleProblem(identity,valid,bounds,OracleContract("discrete";domain=:permutation))
    @test_throws ArgumentError run_metaheuristics(bad)
    @test_throws ArgumentError run_metaheuristics(problem;population=3)
end
