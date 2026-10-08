using MetaStrategist, Test, SHA
import MetaStrategist: canonical_value

@testset "Portable identity golden encodings" begin
    samples=(nothing=>"n;",true=>"b1;",false=>"b0;",:α=>"ys2:α",
        "λ\n"=>"s3:λ\n",Int8(-3)=>"iInt8:-3;",UInt128(7)=>"iUInt128:7;",
        () => "t;",(b=false,a=(nothing,:x))=>"mys1:atn;ys1:x;ys1:bb0;;")
    for (value,expected) in samples
        @test canonical_value(value)==expected
        @test SHA.sha256(canonical_value(value))==SHA.sha256(expected)
    end
    for value in (Float16(-0.0),Float32(Inf),Float64(NaN),
            reinterpret(Float64,0x7ff8000000000001))
        @test canonical_value(value)=="f$(sizeof(value)):$(bitstring(value));"
    end
    @test canonical_value((a=1,b=2))==canonical_value((b=2,a=1))
    @test canonical_value((a=Float64(-0.0),))!=canonical_value((a=Float64(0.0),))
    for value in ("/absolute","\\\\server\\file","C:\\file",[1,2],Dict(:a=>1),big(3))
        @test_throws ArgumentError canonical_value(value)
    end
end
