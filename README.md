# Causifyxion.jl 

[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://TyronCameron.github.io/NewPackage.jl/dev)
[![Test workflow status](https://github.com/TyronCameron/NewPackage.jl/actions/workflows/Test.yml/badge.svg?branch=main)](https://github.com/TyronCameron/NewPackage.jl/actions/workflows/Test.yml?query=branch%3Amain)
[![Coverage](https://codecov.io/gh/TyronCameron/NewPackage.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/TyronCameron/NewPackage.jl)
[![Docs workflow Status](https://github.com/TyronCameron/NewPackage.jl/actions/workflows/Docs.yml/badge.svg?branch=main)](https://github.com/TyronCameron/NewPackage.jl/actions/workflows/Docs.yml?query=branch%3Amain)



Create causal, sampleable random variables. 

Features:

- Focus on variables, not sampling methods or distributions. (Use `Distributions.jl` to get that stuff).
- Organise the causal (one-way dependency) relationships between variables. 
- Turn any type into a random variable.


## Todo

- change `rand!` to `simulate!`. This wording aligns better with reactivity, caching, etc

## Todo but out of scope for now 

- Need a nice way to do 

Would be nice to have a register as well so that you can access those nodes at constant time later.

```julia
@causify begin
	config = Dict(...) # useful for how simulations are done ? 
	my_actions = ( # can be varied later in a nice way
		a => 100,
		b => 200
	)
	x = ...
	y = ... 
end 
```

Would also be nice to have something like this 

```yaml

VARIABLE_A:
	defn: VAR_B + VAR_C
	- VAR_B 
	- VAR_C

VARIABLE_B:
	distr: Normal(0,1)

VARIABLE_C:
	const: 500

```


