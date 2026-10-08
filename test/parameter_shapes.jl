module ParameterShapeTests
using Test, MetaStrategist, SHA
const MS=MetaStrategist

function key_order(value::NamedTuple)
    records=sort!([string(key)=>key for key in keys(value)];by=first)
    Tuple(last(record) for record in records)
end
function reference_shape(value::NamedTuple)
    names=key_order(value)
    NamedTuple{names}(Tuple(reference_shape(getproperty(value,key)) for key in names))
end
reference_shape(value::Tuple)=map(reference_shape,value)
reference_shape(value)=string(typeof(value))
function reference_normalize(value::NamedTuple)
    names=key_order(value)
    NamedTuple{names}(Tuple(reference_normalize(getproperty(value,key)) for key in names))
end
reference_normalize(value::Tuple)=map(reference_normalize,value)
reference_normalize(value)=value

struct CustomScalar{T}
    value::T
end
struct CustomInteger <: Integer
    value::Int
end

@testset "Scalar shapes retain exact type labels and custom display fallback" begin
    samples=(nothing,true,false,:α,"text",Float16(-0.0),Float32(Inf),NaN,
        reinterpret(Float64,0x7ff8000000000001),Int8(-2),Int16(-2),Int32(-2),
        Int64(-2),Int128(-2),UInt8(2),UInt16(2),UInt32(2),UInt64(2),UInt128(2))
    for value in samples
        @test MS._parameter_shape(value)==string(typeof(value))
        @test MS._normalize_strategy_value(value)===value
    end
    for value in (CustomScalar(1),CustomScalar(1.0),CustomInteger(2),1+2im,Char('é'))
        @test MS._parameter_shape(value)==string(typeof(value))
        @test MS._normalize_strategy_value(value)===value
    end
end

@testset "Nested shape and normalization keys preserve byte order and identities" begin
    names=(Symbol(""),:a,:aa,:A,:Z,:z,:_,:path,:sha256,:α,:β,:é,
        Symbol("é"),Symbol("🙂"),Symbol("\n"),Symbol("\x01"),Symbol("a/b"),
        Symbol("C:x"),Symbol("a:b"),Symbol("a\\b"))
    for left in names,right in names
        left==right && continue
        value=NamedTuple{(right,left)}(((;z=(Int8(-1),Float32(-0.0),nothing),a=:α),
            ((;β="text",A=UInt128(7)),reinterpret(Float64,0x7ff8000000000001))))
        shape=MS._parameter_shape(value);normalized=MS._normalize_strategy_value(value)
        expected_shape=reference_shape(value);expected_normalized=reference_normalize(value)
        @test shape==expected_shape
        @test isequal(normalized,expected_normalized)
        @test MS.canonical_value(shape)==MS.canonical_value(expected_shape)
        @test MS.canonical_value(normalized)==MS.canonical_value(expected_normalized)
        @test MS.canonical_value(normalized)==MS.canonical_value(value)
    end
    for value in ((;),(),(;z=(;),a=((),(;))))
        @test MS._parameter_shape(value)==reference_shape(value)
        @test MS._normalize_strategy_value(value)==reference_normalize(value)
    end
end
end
