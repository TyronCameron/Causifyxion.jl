using Taproots, Test

include(joinpath(@__DIR__, "examples.jl"))

###########################################################################
# Run tests
###########################################################################

include(joinpath(@__DIR__, "taproot.jl"))
include(joinpath(@__DIR__, "traversal.jl"))
include(joinpath(@__DIR__, "children.jl"))
include(joinpath(@__DIR__, "flags.jl"))
include(joinpath(@__DIR__, "indexing.jl"))
include(joinpath(@__DIR__, "adjacency.jl"))
include(joinpath(@__DIR__, "modification.jl"))

