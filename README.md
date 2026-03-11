# Causifyxion.jl 

[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://TyronCameron.github.io/Causifyxion.jl/dev)
[![Test workflow status](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/test.yml/badge.svg)](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/test.yml)
[![Coverage](https://codecov.io/gh/TyronCameron/Causifyxion.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/TyronCameron/Causifyxion.jl)
[![Docs workflow Status](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/doc.yml/badge.svg)](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/doc.yml)

Create and manage causally-related variables. 

That includes:

- Setting up functions which run when needed but whose results are otherwise cached
- Setting up variables which depend on each other, and assisting with reactivity (setting downstream variables based on upstream information)
- Setting up random, sampleable variables from a `Distribution`, or any other sampleable method. 

The principle is straightforward: you create a variable (instead of a distribution or function), and you specify the dependencies. 

```julia
x = causify(Uniform(0, 1)) # create a Causal Variable called `x`. This variable can be sampled from. 
y = causify(x) do x # now create Causal Variable called `y`, capturing `x` as a dependency, and setting the value of `y` to be `x^2`
	x^2
end 
```

Now we can easily calculate `y` given `x`. All we need to do is:

```julia
setvalue!(x, 0.9)
simulate!(y) # == 0.81 
```

It is crucial that this package mutates the state of Causal Variables, and variables continue to have the same value until they are set as unknown. This can cause trouble in some circumstances. The `!` functions can cause mutations not only to Causal Variables, but also the variables it depends on. 

## Todo

- change `rand!` to `simulate!` (or similar). This wording aligns better with reactivity, caching, etc
- make `simulate!` = `rand_and_reset!` so that global state is always (kind of) set to `unknown!`. 
- create a function to uproot all values and set unknown above it, invalidating all downstream variables. 

