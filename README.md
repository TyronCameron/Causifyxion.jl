# Causifyxion.jl 

[![Development documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://TyronCameron.github.io/Causifyxion.jl/dev)
[![Test workflow status](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/test.yml/badge.svg)](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/test.yml)
[![Coverage](https://codecov.io/gh/TyronCameron/Causifyxion.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/TyronCameron/Causifyxion.jl)
[![Docs workflow Status](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/doc.yml/badge.svg)](https://github.com/TyronCameron/Causifyxion.jl/actions/workflows/doc.yml)
[![Aqua QA](https://juliatesting.github.io/Aqua.jl/dev/assets/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Causifyxion is a library to help create and manage causally-related variables. 

That includes:

- Setting up functions which run when needed but whose results are otherwise cached.
- Tracking dependencies between variables. 
- Setting up random, sampleable variables from a `Distribution`, or any other sampleable method. 

The original intention behind this package was to build a statistical (random) library with a sampling- or variable-first approach. However, the naming in this package has been kept general to facilitate thinking in a broader scope. As such, there is no requirement that any variable needs to come from a sampleable distribution. 

The principle is straightforward: you create a variable (instead of a distribution or function), and you specify the dependencies. At it's simplest we might have:

```julia
using Dates
x = causify() do # `x` is "Yes" in the first half a minute, and "No" otherwise
	Dates.second(now()) < 30 ? "Yes" : "No"
end 

@assert x isa CausalVariable 
@assert eltype(x) <: String
```

Up to this point, `x` is just a container for a mechanism to sample the value. It has no inherent value itself yet. Indeed if we try to look inside the variable:

```julia
getvalue(x) # throws a `ValueUnknownError`
```

Instead we can resolve the value of the variable (if it does not have a value already) by executing the function inside it:

```julia
underlying_value = resolve!(x) # returns either "Yes" or "No"
```

`resolve!` also sets the value of `x`, so that:

```julia
@assert getvalue(x) == underlying_value
```

Calling `resolve!` repeatedly will yield the exact same result, even if 30 seconds passes, because the resolved value is stored. We can restore a fresh state on `x` by using: 

```julia
refresh!(x)
getvalue(x) # throws a `ValueUnknownError`
```

Finally, we can create a Directed Acyclic Graph (DAG) for `CausalVariables`. For example:

```julia
using Distributions
y = causify(Uniform(0,1))

z = causify(x, y) do x, y 
	length(x) * 500 + y 
end 

@assert eltype(z) <: Float64 # type stability preserved

@assert resolve!(z) == length(getvalue(x)) * 500 + getvalue(y)
```

When I call `resolve!(z)`, it will act on the entire dependency tree (i.e. recursively) of `z`. Same thing when I call `refresh!`. 

```julia
refresh!(z) 

xvals, yvals, zvals = simulate(10, x, y, z) # get back a tuple of data you can easily destructure

# or turn your data into a DataFrame
using DataFrames
df = DataFrame(collect(simulate(10, x, y, z)), [:x, :y, :z])
```

Finally, it's possible to invalidate all downstream caches between a parent and an invalid cache item recursively, as follows: 

```julia
resolve!(z) # ensure we have some values
invalidate!(z, x) # invalidate all causal vars between `z` and `x` (taking every possible route to get there). If `z` depends on all of `x`'s upstream consumers, then all upstream consumers will be set unknown. 

@assert isunknown(x)
@assert isunknown(z)
@assert isknown(y)
```

It is crucial that this package mutates the state of Causal Variables, and variables continue to have the same value until they are set as unknown. Used incorrectly, this is can cause spooky action at a distance. Treat the `!` functions as recursive mutations in this package. 

