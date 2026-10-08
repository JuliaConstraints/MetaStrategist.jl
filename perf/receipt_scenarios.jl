module ReceiptScenarios
using MetaStrategist, SHA
const MS=MetaStrategist
const EXPECTED_IDENTITY="25a7266a635bbf302e08020924a6ff7c4095da747183105bd127994293632f2e"

"A deterministic preparation receipt with the same nested provenance topology as owned units."
function description()
    files=ntuple(i->(;path="src/phase_$i.jl",sha256=bytes2hex(SHA.sha256("phase-$i"))),64)
    (;schema="preparation-receipt/1",unit="owned-1",
        component=(;selection=:worst,depth=(0,1),tabu=(;local_tenure=10,pick=5)),
        execution=(;key="portable-fixture",shape="typed-fixture",requested=:typed,effective=:typed,
            reason="explicit typed realization",plan=(;inputs=(:search,),phases=(:step,))),
        model_revision=UInt64(7),provenance=((;module_name="Fixture",version="1",status=:source_inventory,files),),
        resources=(;threads=2,model=(;scope=:process_local,identity="fixture",
            evaluator_types=ntuple(_->"Fixture.SumEvaluator{Int64}",32)),cost_contract=:incremental))
end

function canonical_case(parameters)
    repetitions=get(parameters,"repetitions",32)
    prepare=description
    operation=state->begin
        result=""
        for _ in 1:repetitions;result=MS.canonical_value(state);end
        result
    end
    verify=(state,result)->bytes2hex(SHA.sha256(result))==EXPECTED_IDENTITY
    (;prepare,operation,verify)
end

function receipt_case(parameters)
    repetitions=get(parameters,"repetitions",32)
    prepare=description
    operation=state->begin
        result=nothing
        for _ in 1:repetitions
            result=MS.preparation_receipt(;unit=state.unit,component=state.component,
                execution=state.execution,model_revision=state.model_revision,
                provenance=state.provenance,resources=state.resources)
        end
        result
    end
    verify=(state,result)->result.identity==EXPECTED_IDENTITY &&
        result.component==state.component && result.resources==state.resources
    (;prepare,operation,verify)
end
end
canonical_case(p)=ReceiptScenarios.canonical_case(p)
receipt_case(p)=ReceiptScenarios.receipt_case(p)
