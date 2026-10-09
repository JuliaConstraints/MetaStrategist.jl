module ArchiveScenarios
using MetaStrategist, SHA, TOML
include("receipt_scenarios.jl")
include("resolution_scenarios.jl")
const MS = MetaStrategist
const GOLDEN = (
    receipt=(canonical="8df886b8cd4ddbd13642d0547fcd0f9c5abe6bcba176df3c468d8f25107cfb1e",
        encoded="822e588acef9edabae7c156cc60977b8e48ae66f239cdaea8c5583f1b366079d",
        file="60a78b092cb99af8f32314765694e99f5ad4c941e43d9a0b288a4a3a4ddd69fb"),
    small_ir=(canonical="c86a17b65a873c71beaf0b3bb44ef5459b4b5ab593c1ab95ad0b0572aea854bf",
        encoded="2d8a1bf56025775dbad60011d6a66c547108a711b3479fa78d01126267cd83f8",
        file="d6a0fcb81ba88c90fb25e602c8deb7dac3842d60cf2662cc1dfa595b821e2961"),
    large_ir=(canonical="98ff7b481cd750b4beae8872f63813f8d5185fc11299c12212fc3ae8bdf7d781",
        encoded="64bc385b1201efcbb9265139294b40db9e09d900a4b291b5825d2d89024f678d",
        file="00b388bb39c59204bb0a3a887a52f73250c1c93fec88e0f20864c7080e5fc486"))
digest(value) = bytes2hex(SHA.sha256(value))
function fixture(name)
    if name == "receipt"
        d = ReceiptScenarios.description()
        record = MS.preparation_receipt(;unit=d.unit, component=d.component,
            execution=d.execution, model_revision=d.model_revision,
            provenance=d.provenance, resources=d.resources)
        return (;value=MS.receipt_snapshot(record), record, catalog=nothing)
    end
    name in ("small_ir", "large_ir") || throw(ArgumentError("archive fixture $name"))
    f = ResolutionScenarios.fixture(name == "small_ir" ? 3 : 129, "chain")
    record = MS.resolve_strategy(f.catalog, f.profile; roots=f.roots)
    (;value=MS.strategy_snapshot(record), record, catalog=f.catalog)
end
function encode_case(parameters)
    name = get(parameters, "fixture", "receipt")
    repetitions = get(parameters, "repetitions", 32)
    prepare = () -> fixture(name)
    operation = state -> begin
        result = nothing
        for _ in 1:repetitions
            result = MS._encode_strategy_value(state.value)
        end
        result
    end
    golden = getproperty(GOLDEN, Symbol(name))
    verify = (state, result) ->
        digest(MS.canonical_value(MS._decode_strategy_value(result))) == golden.canonical &&
        digest(sprint(io -> TOML.print(io, result; sorted=true))) == golden.encoded
    (;prepare, operation, verify)
end
function write_case(parameters)
    name = get(parameters, "fixture", "receipt")
    repetitions = get(parameters, "repetitions", 1)
    prepare = () -> fixture(name)
    operation = state -> begin
        result = nothing
        for _ in 1:repetitions
            directory = mktempdir()
            try
                path = joinpath(directory, "checkpoint.toml")
                value = if name == "receipt"
                    MS.write_preparation_receipt(path, state.record)
                    MS.read_preparation_receipt(path)
                else
                    MS.write_strategy_snapshot(path, state.record)
                    MS.strategy_snapshot(MS.read_strategy_snapshot(path, state.catalog))
                end
                result = (;file=bytes2hex(open(SHA.sha256, path)),
                    canonical=digest(MS.canonical_value(value)))
            finally
                rm(directory; recursive=true)
            end
        end
        result
    end
    golden = getproperty(GOLDEN, Symbol(name))
    verify = (state, result) -> result == (;file=golden.file, canonical=golden.canonical)
    (;prepare, operation, verify)
end
end
archive_encode_case(p) = ArchiveScenarios.encode_case(p)
archive_write_case(p) = ArchiveScenarios.write_case(p)
