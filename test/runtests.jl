using Causifyxion
using Test, Distributions, Aqua
using DataFrames: DataFrame

include(joinpath(@__DIR__, "unit", "causify.jl"))
include(joinpath(@__DIR__, "unit", "macro.jl"))
include(joinpath(@__DIR__, "unit", "replicate.jl"))
include(joinpath(@__DIR__, "unit", "tuple_variants.jl"))
include(joinpath(@__DIR__, "unit", "basis.jl"))
include(joinpath(@__DIR__, "unit", "populations.jl"))
include(joinpath(@__DIR__, "unit", "probabilities.jl"))
include(joinpath(@__DIR__, "unit", "simulate.jl"))
include(joinpath(@__DIR__, "unit", "docs.jl"))

# Set project extras to false. It is erroring due to using Distributions: Distribution
Aqua.test_all(Causifyxion; project_extras = false)
