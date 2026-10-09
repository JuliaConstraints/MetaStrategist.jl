module ArchiveFloatScenarios
using MetaStrategist, SHA, TOML
const MS = MetaStrategist
const GOLDEN = Dict(
    32 => (canonical="cfd5df411aa65fa1d4866aec1f49dd65673faaa643c654adfec47aa67984deea",
        file="f0267b2c453a1530b3979d5d3354d9b3ffba9b84d9ad98fbee8c5217257b346e"),
    128 => (canonical="4465132fee8bfba201265da82b8b3f8a82fdbdc7ed56454277dfb545db5d9eba",
        file="e5dda41fa9928fefa2254c7f7f77aee2222dafed2662a47cad18efe7d482819a"),
    512 => (canonical="25866fe0e2a52e64fd6c1b043beb65064ba277b03ecd1e490019185dd52bbbe6",
        file="04cadb426284654c59cadd760d1d688282f8c6c6d1c1895c65af5ea14eed78b1"))
digest(value) = bytes2hex(SHA.sha256(MS.canonical_value(value)))

function receipt(count)
    coefficients = ntuple(count) do index
        (;half=reinterpret(Float16,UInt16(mod(977*index,65536))),
            single=reinterpret(Float32,UInt32(index)*0x9e3779b9),
            double=reinterpret(Float64,UInt64(index)*0x9e3779b97f4a7c15))
    end
    MS.preparation_receipt(;unit="float-codec-$count",component=(;coefficients),
        execution=(;requested=:typed,effective=:typed),model_revision=UInt64(7))
end

function encode_case(parameters)
    count = get(parameters,"coefficients",128)
    repetitions = get(parameters,"repetitions",16)
    prepare = () -> MS.receipt_snapshot(receipt(count))
    operation = fixture -> begin
        result = nothing
        for _ in 1:repetitions
            result = MS._encode_strategy_value(fixture)
        end
        result
    end
    verify = (fixture,result) -> digest(MS._decode_strategy_value(result)) == GOLDEN[count].canonical &&
        bytes2hex(SHA.sha256(sprint(io -> TOML.print(io,
            Dict("schema"=>"preparation-receipt/1","receipt"=>result);sorted=true)))) == GOLDEN[count].file
    (;prepare,operation,verify)
end

function decode_case(parameters)
    count = get(parameters,"coefficients",128)
    repetitions = get(parameters,"repetitions",16)
    parsed = get(parameters,"parsed",false)
    prepare = () -> begin
        record = receipt(count)
        encoded = MS._encode_strategy_value(MS.receipt_snapshot(record))
        if parsed
            encoded = TOML.parse(sprint(io -> TOML.print(io,encoded;sorted=true)))
        end
        (;encoded)
    end
    operation = fixture -> begin
        value = nothing
        for _ in 1:repetitions
            value = MS._decode_strategy_value(fixture.encoded)
        end
        value
    end
    verify = (fixture,result) -> digest(result) == GOLDEN[count].canonical
    (;prepare,operation,verify)
end

function write_case(parameters)
    count = get(parameters,"coefficients",128)
    repetitions = get(parameters,"repetitions",4)
    prepare = () -> receipt(count)
    operation = record -> begin
        result = nothing
        for _ in 1:repetitions
            directory = mktempdir()
            try
                path = joinpath(directory,"receipt.toml")
                MS.write_preparation_receipt(path,record)
                value = MS.read_preparation_receipt(path)
                result = (;file=bytes2hex(open(SHA.sha256,path)),canonical=digest(value))
            finally
                rm(directory;recursive=true)
            end
        end
        result
    end
    verify = (record,result) -> result == (;file=GOLDEN[count].file,canonical=GOLDEN[count].canonical)
    (;prepare,operation,verify)
end
end
archive_float_encode_case(parameters) = ArchiveFloatScenarios.encode_case(parameters)
archive_float_decode_case(parameters) = ArchiveFloatScenarios.decode_case(parameters)
archive_float_write_case(parameters) = ArchiveFloatScenarios.write_case(parameters)
