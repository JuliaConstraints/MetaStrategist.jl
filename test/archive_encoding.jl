module ArchiveEncodingTests
using Test, MetaStrategist, TOML
const MS = MetaStrategist

@testset "Portable archive encoding preserves exact nested values" begin
    scalars = Any[nothing, false, true, :symbol, "", "λ🌍", "src/relative.jl"]
    for T in (Int8, Int16, Int32, Int64, Int128, UInt8, UInt16, UInt32, UInt64, UInt128)
        append!(scalars, (typemin(T), zero(T), one(T), typemax(T)))
    end
    for (T, U) in ((Float16, UInt16), (Float32, UInt32), (Float64, UInt64))
        append!(scalars, (T(-0.0), T(0.0), T(-1.5), T(1.5), T(-Inf), T(Inf)))
        append!(scalars, (reinterpret(T, U(1)), reinterpret(T, typemax(U)),
            reinterpret(T, reinterpret(U, T(NaN)) | U(1))))
    end
    for scalar in scalars
        for value in (scalar, (scalar,), (;z=(scalar, nothing), a=(;value=scalar)),
                ((;b=scalar, a=(scalar,)), (;a=(scalar,), b=scalar)))
            encoded = MS._encode_strategy_value(value)
            @test MS.canonical_value(MS._decode_strategy_value(encoded)) == MS.canonical_value(value)
            text = sprint(io -> TOML.print(io, encoded; sorted=true))
            @test MS.canonical_value(MS._decode_strategy_value(TOML.parse(text))) == MS.canonical_value(value)
            @test encoded == MS._encode_strategy_value(value)
        end
    end
    named = MS._encode_strategy_value((;z=1, a=2))
    @test named["names"] == ["a", "z"]
    @test MS._encode_strategy_value((;a=2, z=1)) == named
    @test MS._encode_strategy_value(()) == Dict("kind"=>"tuple", "values"=>[])
    @test MS._encode_strategy_value((;)) == Dict("kind"=>"named", "names"=>[], "values"=>[])
end

@testset "Invalid nested archives retain portable validation errors" begin
    outcome(f, value) = try
        f(value)
        nothing
    catch error
        (typeof(error), sprint(showerror, error))
    end
    for invalid in ([], Dict(:a=>1), Ref(1), big(1), BigFloat(1), 1+2im,
            "/absolute/path", "C:\\absolute\\path", "\\\\server\\share")
        for value in (invalid, (invalid,), (;z=1, a=(;value=invalid)),
                ((;ok=:safe), (;invalid,)))
            expected = outcome(MS.canonical_value, value)
            @test expected !== nothing
            @test outcome(MS._encode_strategy_value, value) == expected
        end
    end
end

@testset "Archive writes round-trip and preserve existing history" begin
    receipt = MS.preparation_receipt(;unit="codec-test",
        component=(;amount=Int32(2), nested=(;bits=Float64(-0.0), values=(true,:phase))),
        execution=(;requested=:typed, effective=:typed), model_revision=UInt64(7))
    snapshot = MS.receipt_snapshot(receipt)
    directory = mktempdir()
    try
        path = joinpath(directory, "nested", "receipt.toml")
        @test MS.write_preparation_receipt(path, receipt) == abspath(path)
        @test MS.canonical_value(MS.read_preparation_receipt(path)) == MS.canonical_value(snapshot)
        contents = read(path)
        @test_throws ArgumentError MS.write_preparation_receipt(path, receipt)
        @test read(path) == contents
        @test readdir(dirname(path)) == ["receipt.toml"]
    finally
        rm(directory; recursive=true)
    end
end
end
