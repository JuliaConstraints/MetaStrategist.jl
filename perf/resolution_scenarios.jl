module ResolutionScenarios
using MetaStrategist
const MS = MetaStrategist
const GOLDEN_KEYS = (
    chain_3=("682ec1be2450d64dd211fc5d3ca63fe8b4fa2694b29820bebb175a79507e2c50", "5b0593b85f0522b2f625ba8943c6e43c5a985a72ad3a0106c4812e194106b06d"),
    chain_64=("fd1e9b81c153c093bdaef8133be8caaee7e3519fdbaebcd68f32f317f8857021", "656e8a8390b10a24acc6194e5954614dd2e4cdd0640bfd50ccb19bb6c3f7c418"),
    chain_129=("da101844e1dae44b26022ccd975b049ed0f80fb2899585f60d4965a30f914e1d", "98484552a9e2742665f96240126e29a1ded649841c1302ed889346e78380d3ed"),
    wide_64=("29e8e430f93608e4c42bc0acdf8e23bc4784f7055fe1809e7a8a01bc0c622b2f", "800e7d886924bd3f350df45fdf7e5d40cb5bddc2cff2dac6771eb5e7d0f935d8"),
    layers_64=("64acbf28014503cd81688093e209dec8992e5dda021fbabd042c82fa132baa90", "3cc4d033306af140e188b37abb4b42b24646e8d2f8bb43260114cefad53576fa"))
struct NoOpPhase end
(::NoOpPhase)(context) = nothing
phase_factory(parameters, context) = NoOpPhase()

function fixture(count, topology)
    roles = [Symbol(:phase,index) for index in 1:count]
    catalog = MS.PhaseCatalog()
    defaults = Dict{Symbol,MS.PhaseChoice}()
    width = 16
    for index in 1:count
        dependencies = if topology == "chain"
            index == 1 ? () : (roles[index-1],)
        elseif topology == "wide"
            ()
        elseif topology == "layers"
            layer = (index-1)÷width
            layer == 0 ? () : Tuple(roles[((layer-1)*width+1):(layer*width)])
        else
            throw(ArgumentError("unknown resolution topology"))
        end
        MS.register_phase!(catalog, MS.PhaseDefinition(roles[index], :noop, phase_factory;
            dependencies, owns=(Symbol(:resource,index),)))
        defaults[roles[index]] = MS.PhaseChoice(:noop; amount=index)
    end
    expected = if topology == "chain"
        roles
    elseif topology == "wide"
        sort(roles; by=string)
    else
        reduce(vcat, (sort(roles[start:min(start+width-1,count)]; by=string)
            for start in 1:width:count))
    end
    (;catalog, profile=MS.StrategyProfile(:resolution,"1",defaults), roots=Tuple(reverse(roles)), expected)
end

function resolution_case(parameters)
    count = get(parameters, "phases", 64)
    topology = get(parameters, "topology", "chain")
    repetitions = get(parameters, "repetitions", 16)
    prepare = () -> fixture(count, topology)
    operation = fixture -> begin
        result = nothing
        for _ in 1:repetitions
            result = MS.resolve_strategy(fixture.catalog, fixture.profile; roots=fixture.roots)
        end
        result
    end
    golden = get(GOLDEN_KEYS, Symbol(topology,"_",count), nothing)
    verify = (fixture, result) ->
        [phase.definition.category for phase in result.phases] == fixture.expected &&
        length(result.phases) == count && isempty(result.inputs) && isempty(result.capabilities) &&
        (golden === nothing || (result.semantic_key, result.shape_key) == golden)
    (;prepare, operation, verify)
end
end
resolution_case(p) = ResolutionScenarios.resolution_case(p)
