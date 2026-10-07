module MetaStrategistMetaheuristicsExt
import MetaStrategist as MS
import Metaheuristics as MH

"Native DE route: box domains, scalar objective, native (f,g,h), final verification only."
function MS.run_metaheuristics(problem::MS.OracleProblem;
        evaluations::Integer=64,population::Int=8,iterations::Int=8,seed::Integer=1)
    adapter=MS.AdapterContract("Metaheuristics.DE/native",string(Base.pkgversion(MH)),
        (:continuous,),true,false,false)
    decision=MS.adapter_decision(problem,adapter)
    decision.allowed || throw(ArgumentError(join(decision.reasons,"; ")))
    population>=4 && evaluations>=population && iterations>0 && seed>=0 ||
        throw(ArgumentError("DE needs population>=4, evaluations>=population, iterations>0 and seed>=0"))
    bounds=problem.bounds
    bounds isa AbstractMatrix && size(bounds,1)==2 && size(bounds,2)>0 &&
        all(isfinite,bounds) && all(bounds[1,:].<bounds[2,:]) ||
        throw(ArgumentError("native DE requires finite 2-by-n strict box bounds"))
    # A dedicated task isolates the solver's seed! from the caller's task-local RNG.
    fetch(@async begin
        session=MS.OracleSession(problem;evaluations)
        objective=x->begin
            result=MS.evaluate!(session,x)
            if problem.contract.constraints
                result isa Tuple && length(result)==3 || throw(ArgumentError("constrained oracle must return (f,g,h)"))
                f,g,h=result
                f isa Real && isfinite(f) && g isa AbstractVector && h isa AbstractVector &&
                    all(isfinite,g) && all(isfinite,h) || throw(ArgumentError("invalid constrained oracle output"))
            else
                result isa Real && isfinite(result) || throw(ArgumentError("oracle must return a finite scalar objective"))
            end
            result
        end
        options=MH.Options(;iterations,f_calls_limit=evaluations,seed,
            parallel_evaluation=false,verbose=false,debug=false,store_convergence=false)
        algorithm=MH.DE(N=population,options=options)
        stopped_by=:solver
        try
            MH.optimize(objective,copy(bounds),algorithm)
        catch error
            error isa MS.OracleBudgetExceeded || rethrow()
            stopped_by=:evaluation_limit
        end
        result=MS.oracle_result(session,MH.minimizer(algorithm.status))
        (;result...,stopped_by,adapter=decision,completed_iterations=algorithm.status.iteration,
            native_evaluations=algorithm.status.f_calls)
    end)
end
end
