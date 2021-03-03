using MetaStrategist
using Documenter

DocMeta.setdocmeta!(MetaStrategist, :DocTestSetup, :(using MetaStrategist); recursive=true)

makedocs(;
    modules=[MetaStrategist],
    authors="Khalil CHRIT",
    repo="https://github.com/JuliaConstraints/MetaStrategist.jl/blob/{commit}{path}#{line}",
    sitename="MetaStrategist.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        canonical="https://JuliaConstraints.github.io/MetaStrategist.jl",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaConstraints/MetaStrategist.jl",
    devbranch="main",
)
