@testset "Aqua.jl" begin
    import Aqua
    import MetaStrategist

    Aqua.test_all(MetaStrategist; deps_compat = false)
    Aqua.test_deps_compat(MetaStrategist; check_extras = false)
end
