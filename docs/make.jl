using Documenter
using Causifyxion

push!(LOAD_PATH,"../src/")

makedocs(
    sitename = "Causifyxion",
    format = Documenter.HTML(),
    modules = [Causifyxion],
    pages = [
        "Index" => "index.md",
        "API" => "api.md"
    ]
)

deploydocs(
    repo = "github.com/TyronCameron/Causifyxion.jl.git",
    devbranch = "main"
)
