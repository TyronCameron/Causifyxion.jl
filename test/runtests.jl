using Causifyxion
using Test, Distributions, Aqua
using DataFrames: DataFrame

include(joinpath(@__DIR__, "causify.jl"))
include(joinpath(@__DIR__, "macro.jl"))

# Set project extras to false. It is erroring due to using Distributions: Distribution
Aqua.test_all(Causifyxion; project_extras = false)
