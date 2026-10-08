using Test
using TestItemRunner
using TestItems

@testset "MetaStrategist.jl" begin
    include("canonical_encoding.jl")
    include("Aqua.jl")
    include("TestItemRunner.jl")
    include("specialization.jl")
    include("preparation_services.jl")
end
