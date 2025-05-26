using Documenter
using Causifyx

push!(LOAD_PATH,"../src/")

makedocs(
    sitename = "Causifyx",
    format = Documenter.HTML(),
    modules = [Causifyx],
    pages = [
        "Index" => "index.md",
        "API" => "api.md"
    ]
)

deploydocs(
    repo = "github.com/TyronCameron/Causifyx.jl.git",
    devbranch = "main"
)
