using Test
using TestItemRunner
using TestItems

@testset "MetaStrategist.jl" begin
    include("canonical_encoding.jl")
    include("parameter_shapes.jl")
    include("Aqua.jl")
    include("TestItemRunner.jl")
    include("specialization.jl")
    include("resolution_order.jl")
    include("capability_filtering.jl")
    include("preparation_services.jl")
    include("reference_preparation.jl")
end
