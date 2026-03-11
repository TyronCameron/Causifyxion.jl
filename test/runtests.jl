using Causifyxion
using Test, Distributions, Aqua

include(joinpath(@__DIR__, "causify.jl"))
include(joinpath(@__DIR__, "macro.jl"))

Aqua.test_all(Causifyxion)
