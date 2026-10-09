module ResourceResolutionScenarios
using MetaStrategist, SHA
include("resolution_scenarios.jl")
using .ResolutionScenarios
const MS = MetaStrategist
const GOLDEN_KEYS = (
    chain_3=("3465ae9468c433348e6beb28d1292d4d66f9fed0d4d30f3b8cb1abae8b1d88c5","d921d04e37b753be2f6a91b24079eba67acf07965ef4510f835c17124896f74e","253e93ec632e417255f6b98a6d23f46225edd0365341bcb3c3b326a8b8f53fae"),
    chain_64=("7b78ef6e4683fbcbdceddc141f73d903e7e0909807935a1cf3fcf3ab2d914788","ca26ee7a3eb539d74192d1d6adebfaba46f1eb1d18a1fb95c216264963a574aa","9a56f3bde3ebacb79e8dd2b9b720d73d248d570a6c6fae17802a3f2ad639fb49"),
    chain_129=("0f39fe4e8ef0dc4481fcd1d27b9ed046af9ee99c18cc26decb3656491f5925b4","66adaab01687b43c9ca41e4c6033811082e8eb52e013cb153e97ac4f5b8bfce0","4a0d1dfdf50dca7ac8ea48f81b21be4e323319ab85631aad809f5e948802b9cd"),
    wide_64=("e66fc3dfac944708ed117075a0deb413f8705ba3a2a22f473219d551fb128d49","cdc3fd7d1e315d31dbdf925ded91a5cd670f57b6e911a0126ff20d4341d0f7a0","442039d2a979f98d88974defce18dea7d33ee51839142d72df6b2f4be1fcac43"),
    layers_64=("f905b8d53aa0a7b1bf7bb6b7d2172f1f48a932867ef369a4d6ab96ba62220963","50dc7c949c5a9b06295e228923d2d91acce1a2f11ce2a4c97326777e160729de","dada2ea30994c68152cf8c9903af0923b772e9d745703065bac2066b5cce4af9"))

function fixture(count, topology)
    base = ResolutionScenarios.fixture(count, topology)
    roles = [Symbol(:phase,index) for index in 1:count]
    catalog = MS.PhaseCatalog()
    width = 16
    for index in 1:count
        original = base.catalog.definitions[(roles[index],:noop,"1")]
        reads, writes, invalidates, requires = if topology=="chain"
            ((:state,), (:state,), (:state,), (Symbol(:capability,index-1),))
        elseif topology=="wide"
            ((:source,), (Symbol(:resource,index),), (), (:initial,))
        else
            layer = (index-1)÷width
            prior = layer==0 ? () : ((layer-1)*width+1):(layer*width)
            (layer==0 ? (:source,) : Tuple(Symbol(:resource,p) for p in prior),
                (Symbol(:resource,index),), (),
                layer==0 ? (:initial,) : Tuple(Symbol(:capability,p) for p in prior))
        end
        MS.register_phase!(catalog,MS.PhaseDefinition(roles[index],:noop,
            ResolutionScenarios.phase_factory; dependencies=original.dependencies,
            owns=original.owns,reads,writes,invalidates,requires,
            provides=(Symbol(:capability,index),)))
    end
    inputs = topology=="chain" ? (:state,) : (:source,)
    capabilities = topology=="chain" ? (:capability0,) : (:initial,)
    (;catalog,base.profile,base.roots,base.expected,inputs,capabilities)
end

function resource_resolution_case(parameters)
    count = get(parameters,"phases",64)
    topology = get(parameters,"topology","chain")
    repetitions = get(parameters,"repetitions",16)
    prepare = () -> fixture(count,topology)
    operation = fixture -> begin
        result = nothing
        for _ in 1:repetitions
            result = MS.resolve_strategy(fixture.catalog,fixture.profile;
                roots=fixture.roots,inputs=fixture.inputs,capabilities=fixture.capabilities)
        end
        result
    end
    golden = get(GOLDEN_KEYS,Symbol(topology,"_",count),nothing)
    verify = (fixture,result) ->
        [phase.definition.category for phase in result.phases]==fixture.expected &&
        length(result.phases)==count && result.inputs==fixture.inputs &&
        result.capabilities==fixture.capabilities &&
        (golden===nothing || (result.semantic_key,result.shape_key,
            bytes2hex(SHA.sha256(MS.canonical_value(MS.strategy_snapshot(result)))))==golden)
    (;prepare,operation,verify)
end
end
resource_resolution_case(parameters) = ResourceResolutionScenarios.resource_resolution_case(parameters)
