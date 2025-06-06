# include(joinpath(dirname(@__DIR__), "src", "Causifyxion.jl"))
# using .Causifyxion
using Causifyxion
using Test, Distributions

include(joinpath(@__DIR__, "causify.jl"))
include(joinpath(@__DIR__, "macro.jl"))

