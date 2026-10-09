module ArchiveFloatDecodingTests
using Test, MetaStrategist, Random
const MS = MetaStrategist

@testset "Portable float decoding preserves every Float16 bit pattern" begin
    for bits in 0:65535
        word = UInt16(bits)
        record = Dict("kind"=>"float","type"=>"Float16","bits"=>bitstring(word))
        value = MS._decode_strategy_value(record)
        @test value isa Float16 && reinterpret(UInt16,value) == word
    end
end

@testset "Portable float decoding preserves wider scalar bits" begin
    rng = MersenneTwister(929)
    for (T,U) in ((Float32,UInt32),(Float64,UInt64))
        words = [zero(U),one(U),typemax(U),reinterpret(U,T(-0.0)),
            reinterpret(U,T(Inf)),reinterpret(U,T(-Inf)),reinterpret(U,T(NaN))]
        append!(words,rand(rng,U,1024))
        for word in words
            record = Dict("kind"=>"float","type"=>string(T),"bits"=>bitstring(word))
            saved = copy(record)
            value = MS._decode_strategy_value(record)
            @test value isa T && reinterpret(U,value) == word && record == saved
        end
    end
end

function reference(record)
    record["kind"] == "float" || error("the reference only handles float records")
    T,U = Dict("Float16"=>(Float16,UInt16),"Float32"=>(Float32,UInt32),
        "Float64"=>(Float64,UInt64))[record["type"]]
    reinterpret(T,parse(U,record["bits"];base=2))
end
outcome(f,record) = try
    value = f(record)
    (typeof(value),bitstring(value))
catch error
    (typeof(error),sprint(showerror,error))
end

struct LookupProbe
    record::Dict{String,Any}
    accesses::Vector{String}
end
function Base.getindex(probe::LookupProbe,key::String)
    push!(probe.accesses,key)
    probe.record[key]
end

@testset "Malformed float records retain exact errors and access order" begin
    records = Any[
        Dict("kind"=>"float"),
        Dict("kind"=>"float","type"=>"Float16"),
        Dict("kind"=>"float","type"=>"Float128"),
        Dict("kind"=>"float","type"=>:Float16),
        Dict("kind"=>"float","type"=>nothing),
        Dict("kind"=>"float","type"=>16),
        Dict("kind"=>"float","type"=>"Float128","bits"=>"1"),
        Dict("kind"=>"float","type"=>SubString("Float16",1),"bits"=>"1")]
    for type in ("Float16","Float32","Float64"),
            bits in ("","2","-1",repeat("1",129),"00101"," 1 ","+1",1,true,nothing,
                SubString("00101",1),"λ")
        push!(records,Dict{String,Any}("kind"=>"float","type"=>type,"bits"=>bits))
    end
    for record in records
        expected = LookupProbe(Dict{String,Any}(record),String[])
        actual = LookupProbe(Dict{String,Any}(record),String[])
        @test outcome(MS._decode_strategy_value,actual) == outcome(reference,expected)
        @test actual.accesses == expected.accesses
        @test actual.record == expected.record == record
    end
end
end
