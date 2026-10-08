module ParameterScenarios
using MetaStrategist, SHA
const MS=MetaStrategist
include("receipt_scenarios.jl")
const SHAPE_IDENTITY="99259a0c01be70b5554607ba7d1369971ef04acc7a6d1158064760ac849c5409"

function ordered_keys(value::NamedTuple)
    issorted(string.(keys(value))) && all(ordered_keys,values(value))
end
ordered_keys(value::Tuple)=all(ordered_keys,value)
ordered_keys(value)=true

function shape_case(parameters)
    repetitions=get(parameters,"repetitions",32)
    prepare=ReceiptScenarios.description
    operation=state->begin
        result=nothing
        for _ in 1:repetitions;result=MS._parameter_shape(state);end
        result
    end
    verify=(state,result)->ordered_keys(result) &&
        bytes2hex(SHA.sha256(MS.canonical_value(result)))==SHAPE_IDENTITY
    (;prepare,operation,verify)
end

function normalize_case(parameters)
    repetitions=get(parameters,"repetitions",32)
    prepare=ReceiptScenarios.description
    operation=state->begin
        result=nothing
        for _ in 1:repetitions;result=MS._normalize_strategy_value(state);end
        result
    end
    verify=(state,result)->ordered_keys(result) &&
        bytes2hex(SHA.sha256(MS.canonical_value(result)))==ReceiptScenarios.EXPECTED_IDENTITY
    (;prepare,operation,verify)
end
end
parameter_shape_case(p)=ParameterScenarios.shape_case(p)
parameter_normalize_case(p)=ParameterScenarios.normalize_case(p)
