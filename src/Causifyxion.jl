
"""
Causifyxion is a library for creating causally-related variables, and sampling from them.
"""
module Causifyxion

using Taproots
using SumTypes
using Distributions: Distribution

export CausalVariable,
    ValueUnknownError, getvalue, setvalue!, 
    isknown, isunknown,
    isanyknown, isnothingknown, dependson, 
    ValueAlreadyKnownError,
    resolve!, refresh!, simulate!, simulate!,
    causify, @causify

"""
    Possible{T}

A sum type including `Unknown` as well as `Known(x::T)`. 
"""
@sum_type Possible{T} begin
    Unknown
    Known{T}(::T)
end 

"""
    ValueUnknownError

You tried to get the value of a CausalVariable that has not yet been sampled. 
"""
struct ValueUnknownError <: Exception end 

"""
    CausalVariable{T}

A mutable struct, and the main struct that this package provides. 
A CausalVariable is just a wrapper around a mechanism of sampling that variable. Create one using `causify`.

Example: 

```julia
x = causify(Normal(0,1))
```

The point of this struct is to: 

- Keep track of dependencies between variables
- Keep track of sampled values until they are resampled 

This enables you to: 

- Sample from a few dependent variables conveniently without needing to wrap it in one ugly function / closure 
- Manually intervene in the system and resample with your interventions
"""
mutable struct CausalVariable{T}
    value::Possible{T}
    rand::Function
    dependson::Vector{<:CausalVariable}
end
Taproots.children(rv::CausalVariable) = rv.dependson
Base.eltype(::CausalVariable{T}) where T = T
function Base.show(io::IO, rv::CausalVariable) 
    t = eltype(rv)
    v = @cases rv.value begin
        Unknown => "CausalVariable(Unknown::$(t))"
        Known(x) => "CausalVariable($(x)::$(t))"
    end
    show(io, v)
end 

"""
    causify(distr::Distribution)
    causify(rand::Function, [::Type{T},] dependencies::CausalVariable...)

This is the main entrypoint (along with the more convenient @causify) to get a CausalVariable struct. 
There are a few options to call this function.

```julia 
using Distributions

x = causify(Normal(0,1)) # first way 
y = causify(x) do x 
    x^2
end # second way, defines y to be x^2
z = causify(Float64, x, y) do x, y 
    x + y 
end # third way, defines z to be x + y, and type hints at z's eltype. 
```

You may find the type hinting useful in some scenarios. In our case, it is redundant and will automatically be inferred. 
Also see @causify for a more convenient way to call this function. 
"""
causify(rand::Function, ::Type{T}, dependson::CausalVariable...) where T = CausalVariable{T}(Unknown, rand, collect(dependson))
causify(distr::Distribution) = causify(() -> rand(distr), eltype(distr))
function causify(rand::Function, dependson::CausalVariable...) 
    types = Union{Base.return_types(rand, eltype.(dependson))...}
    if types <: Union{} 
        types = Any 
    end 
    causify(rand, types, dependson...)
end 

"""
    getvalue(causalvariable::CausalVariable)

Returns the value that is wrapped within the causalvariable.
"""
getvalue(causalvariable::CausalVariable) = @cases causalvariable.value begin 
    Unknown => error(ValueUnknownError, " Can't get the value of an unknown value! Perhaps call resolve!(your_variable) first. The variable you attempted to get the value of was $causalvariable")
    Known(x) => x
end

"""
    setvalue!(causalvariable::CausalVariable{T}, value::T)

Sets the value that is wrapped within the causalvariable. `value` must be of type `T` where `T` is the eltype of `causalvariable`. 
"""
function setvalue!(causalvariable::CausalVariable{T}, value::T) where T
    causalvariable.value = Known{T}(value)
    return causalvariable
end

"""
    isknown(causalvariable)

`true` is the causalvariable has a known value (i.e. has been previously sampled). `false` otherwise.
""" 
isknown(causalvariable::CausalVariable) = @cases causalvariable.value begin
    Unknown => false 
    Known(x) => true
end

"""
    isknown(causalvariable)

`true` is the causalvariable has a known value (i.e. has been previously sampled). `false` otherwise.
"""
isunknown(causalvariable::CausalVariable) = !isknown(causalvariable)

"""
    setunknown!(causalvariable)

Sets the value of the causal variable back to `Unknown`.
"""
function setunknown!(causalvariable)
    causalvariable.value = Unknown
    return causalvariable
end

"""
    dependson(parent, child)

Checks where the parent depends on the child, recursively. If it doesn't depend, then obviously changing the `child` is not going to change `parent`. 
"""
dependson(parent::CausalVariable, child::CausalVariable) = isparent(parent, child)

"""
    isanyknown(causalvar::CausalVariable...)

Checks whether `causalvar` is known, or any of its dependencies are known. 
"""
isanyknown(causalvar::CausalVariable) = any(isknown, postorder(causalvar))
isanyknown(causalvar::CausalVariable...) = any(isanyknown, causalvar)

"""
    isnothingknown(causalvar::CausalVariable...)

Checks whether `causalvar` is unknown, and all of its dependencies are unknown. 
"""
isnothingknown(causalvar::CausalVariable...) = !isanyknown(causalvar...)

"""
    ValueAlreadyKnownError

You cannot simulate a CausalVariable if some parts of it are already known. 
"""
struct ValueAlreadyKnownError <: Exception end 

"""
    resolve!(causalvariables...)

Samples each of the `causalvariables` supplied and returns the value of those answers. 
If the variable value is already known, it returns that known value.

Example: 

```julia
x = causify(Uniform(0,1))
first_sample = resolve!(x)
second_sample = resolve!(x)

@assert first_sample == second_sample # note that resolve! is not a completely fresh sample. It keeps known values around until you set the CausalVariable to `Unknown`. 
```

`resolve!` recursively modifies all CausalVariables beneath it, by design, because it samples them all. 
"""
function resolve!(causalvariable::CausalVariable)
    if isknown(causalvariable) return getvalue(causalvariable) end
    for child in postorder(causalvariable; connector = (parent, child) -> isunknown(child))
        values = getvalue.(child.dependson)
        setvalue!(child, Base.invokelatest(child.rand, (values...)))
    end 
    return getvalue(causalvariable)
end
resolve!(causalvariable::CausalVariable...) = resolve!.(causalvariable)

"""
    refresh!(rv::CausalVariable...)

In short, this makes the `CausalVariable` forget its current sample so you can resample the CausalVariable. 
Makes each of the `causalvariables` supplied `Unknown` and **recursively** does this for all children. 
To do this non-recursively, rather use `setunknown!`. 

Example: 

```julia
x = causify(Uniform(0,1))
y = @causify x^2

first_sample = resolve!(y)

@assert isknown(x) # This value is sampled through y
@assert isknown(y) # This value is sampled directly 

refresh!(y)

@assert isunknown(x) # This value was refreshed through y
@assert isunknown(y) # This value was refreshed directly 
```
"""
function refresh!(causal_variable::CausalVariable)
    for child in postorder(causal_variable)
        setunknown!(child)
    end 
    return causal_variable
end
refresh!(causalvariable::CausalVariable...) = refresh!.(causalvariable)

"""
    simulate!([intervention_function::Function, n::Int, ]causalvar::CausalVariable...)

Get an absolutely fresh sample of your variables. This will refresh! this and all sub-variables.
You can call this is repeatedly by supplying `n`. Handy for data. 

Warning! This leaves your variables in a known state. 

Examples for a single variable and simulation:

```julia
x = causify(Uniform(0,1))
y = @causify x^2
fresh_sample1 = simulate!(y)
fresh_sample2 = simulate!(y)

@assert fresh_sample1 != fresh_sample2 # these are 100% fresh samples

rigged_value = simulate!(y) do
    setvalue!(x, 0.5)
end 

@assert rigged_value == 0.25 
```

Examples for multiplie simulations:

```julia
x = causify(Uniform(0,1))
y = @causify x^2 # define y as x^2

mat = simulate!(5, x, y) # first column = 5 fresh samples of x, second column = 5 fresh samples of y; those samples are consistent in each row

@assert all(mat[:,1] .^ 2 .== mat[:,2]) # every value in column 1 squared equals every value in column 2

rigged_tuple = simulate!(5, x, y) do
    setvalue!(x, 0.5)
end 

@assert all(rigged_tuple[1] .== 0.5)
@assert all(rigged_tuple[2] .== 0.25)

# and then if you want...
using DataFrames
df = DataFrame(collect(rigged_tuple), [:x, :y])
```
"""
function simulate!(intervention_function!::Function, causalvariable::CausalVariable...)
    refresh!(causalvariable...)
    intervention_function!()
    return resolve!(causalvariable...)
end
simulate!(causalvariable::CausalVariable...) = simulate!(() -> (), causalvariable...)

simulate!(intervention_function!::Function, n::Int, causalvariable::CausalVariable...) = 
    zip((simulate!(intervention_function!, causalvariable...) for _ in 1:n)...) .|> collect |> Tuple
simulate!(n::Int, causalvariable::CausalVariable...) = simulate!(() -> (), n, causalvariable...)

"""
    simulate([intervention_function::Function, n::Int, ]causalvar::CausalVariable...)

Same as `simulate!` but will first check if your variables are known. If already known, it will error. 
This starts and leaves your variables in an unknown state. 

If you encounter errors, try calling `refresh!` before running this. 
"""
function simulate(intervention_function!::Function, causalvariable::CausalVariable...)
    if isanyknown(causalvariable...) 
        error(ValueAlreadyKnownError, "You cannot call `simulate` on variables with known values. Instead call `simulate!` or `refresh!` your variables first. CausalVariable: $causalvariable")
    end 
    intervention_function!()
    values = resolve!(causalvariable...)
    refresh!(causalvariable...)
    return values
end
simulate(causalvariable::CausalVariable...) = simulate(() -> (), causalvariable...)

function simulate(intervention_function!::Function, n::Int, causalvariable::CausalVariable...)
    if isanyknown(causalvariable...) 
        error(ValueAlreadyKnownError, "You cannot call `simulate` on variables with known values. Instead call `simulate!` or `refresh!` your variables first. CausalVariable: $causalvariable")
    end 
    values = zip((simulate!(intervention_function!, causalvariable...) for _ in 1:n)...) .|> collect |> Tuple
    refresh!(causalvariable...)
    return values 
end
simulate(n::Int, causalvariable::CausalVariable...) = simulate(() -> (), n, causalvariable...)

# Include the evil macro 
include(joinpath(@__DIR__, "CausifyMacro.jl"))

end  # module Causifyxion



