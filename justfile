set quiet 

default:
    @just --list

instantiate:
    julia --project=. -e 'using Pkg; Pkg.instantiate()'

test:
    julia --project=. -e 'using Pkg; Pkg.test()'

register:
    julia --project=. -e 'using LocalRegistry; register(registry = "/home/tyronc/.julia/registries/TyPackages.jl/")'

[working-directory('test/benchmark')]
benchmark:
    julia --project=. -e 'using Pkg; Pkg.resolve(); Pkg.instantiate()'
    julia --project=. benchmark.jl