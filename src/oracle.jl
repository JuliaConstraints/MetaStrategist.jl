"Convert event data to immutable, owned values; reject closures, RNGs and handles."
_event_value(x::AbstractArray) = Tuple(_event_value(v) for v in x)
_event_value(x::NamedTuple) = map(_event_value,x)
_event_value(x::Tuple) = map(_event_value,x)
function _event_value(x)
    canonical_value(x)
    x
end
mutable struct EventBuffer
    records::Vector{NamedTuple}
    started_ns::UInt64
    owner::Task
    capacity::Int
    dropped::Int
end
function EventBuffer(;capacity=1024)
    capacity>=0 || throw(ArgumentError("negative event capacity"))
    EventBuffer(NamedTuple[],time_ns(),current_task(),capacity,0)
end
function observe!(sink::EventBuffer, event::Symbol; payload...)
    current_task()===sink.owner || throw(ArgumentError("event buffer belongs to another task"))
    if length(sink.records)>=sink.capacity
        sink.dropped+=1
        return nothing
    end
    data=_event_value((;payload...))
    push!(sink.records,(event=event,elapsed_ns=time_ns()-sink.started_ns,payload=data))
    nothing
end
observe!(::Nothing, event::Symbol;payload...) = nothing
events(sink::EventBuffer) = Tuple(sink.records)

"Identity of the formulation and codec; an error is never the Boolean concept."
struct OracleContract
    id::String
    version::String
    codec::String
    domain::Symbol
    constraints::Bool
    objectives::Int
end
function OracleContract(id::AbstractString;version="1",codec="identity/1",domain=:continuous,
        constraints=false,objectives=1)
    objectives>0 || throw(ArgumentError("an oracle needs objectives"))
    OracleContract(String(id),String(version),String(codec),domain,constraints,objectives)
end
struct OracleProblem{F,C,D,V,B}
    evaluate::F
    concept::C
    decode::D
    valid_domain::V
    bounds::B
    contract::OracleContract
end
OracleProblem(evaluate,concept,bounds,contract::OracleContract;
    decode=identity,valid_domain=x->all(isfinite,x)) =
    OracleProblem(evaluate,concept,decode,valid_domain,bounds,contract)

struct AdapterContract
    id::String
    version::String
    domains::Tuple
    constraints::Bool
    multiobjective::Bool
    anytime::Bool
end
function adapter_decision(problem::OracleProblem, adapter::AdapterContract; require_anytime=false)
    c=problem.contract
    reasons=String[]
    c.domain in adapter.domains || push!(reasons,"unsupported domain $(c.domain)")
    c.constraints && !adapter.constraints && push!(reasons,"adapter would discard constraints")
    c.objectives>1 && !adapter.multiobjective && push!(reasons,"adapter would discard objectives")
    require_anytime && !adapter.anytime && push!(reasons,"no incumbent event contract")
    (;allowed=isempty(reasons),reasons=Tuple(reasons),adapter=(adapter.id,adapter.version),
        formulation=(c.id,c.version,c.codec))
end

struct OracleBudgetExceeded <: Exception end
Base.showerror(io::IO,::OracleBudgetExceeded)=print(io,"oracle evaluation budget exhausted")
"Single-owner session. Counts attempted evaluations, including invalid decodings and failures."
mutable struct OracleSession{P}
    problem::P
    limit::Int
    evaluations::Int
    failures::Int
    oracle_checks::Int
    owner::Task
end
function OracleSession(problem::OracleProblem; evaluations::Integer)
    evaluations>=0 || throw(ArgumentError("negative evaluation budget"))
    OracleSession(problem,Int(evaluations),0,0,0,current_task())
end
function evaluate!(session::OracleSession,x)
    current_task()===session.owner || throw(ArgumentError("oracle session belongs to another task"))
    session.evaluations<session.limit || throw(OracleBudgetExceeded())
    session.evaluations+=1
    try
        decoded=session.problem.decode(copy(x))
        session.problem.valid_domain(decoded) || throw(ArgumentError("decoded candidate violates domain contract"))
        session.problem.evaluate(decoded)
    catch
        session.failures+=1
        rethrow()
    end
end
function oracle_result(session::OracleSession,x)
    current_task()===session.owner || throw(ArgumentError("oracle session belongs to another task"))
    decoded=session.problem.decode(copy(x))
    session.oracle_checks+=1
    valid=session.problem.valid_domain(decoded) && session.problem.concept(decoded)
    valid isa Bool || throw(ArgumentError("concept must return Bool"))
    (;solution=deepcopy(decoded),valid,evaluations=session.evaluations,
        failed_evaluations=session.failures,oracle_checks=session.oracle_checks,
        contract=session.problem.contract,observation=:final_only)
end

"Native adapter entry point, supplied by the Metaheuristics extension when loaded."
function run_metaheuristics end
export run_metaheuristics
