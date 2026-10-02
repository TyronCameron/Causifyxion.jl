
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
    isanyknown, isnothingknown, dependson, isindependent,
    ValueAlreadyKnownError,
    resolve!, refresh!, simulate!, simulate,
    causify, @causify, given

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
    resolver
    dependencies::Vector{<:CausalVariable}
end
Taproots.children(causalvar::CausalVariable) = causalvar.dependencies
Taproots.setchildren!(causalvar::CausalVariable, children) = (causalvar.dependencies = children; causalvar)
Base.eltype(::CausalVariable{T}) where T = T
function Base.show(io::IO, causalvar::CausalVariable) 
    type = eltype(causalvar)
    value = @cases causalvar.value begin
        Unknown => "CausalVariable(Unknown::$(type))"
        Known(x) => "CausalVariable($(x)::$(type))"
    end
    print(io, value)
end 

"""
    causify(distr::Distribution)
    causify(resolver::Function, [::Type{T},] dependencies::CausalVariable...)

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
Also see `@causify` for another convenient way to call this function. 
"""
causify(resolver, ::Type{T}, dependencies::CausalVariable...) where T = CausalVariable{T}(Unknown, resolver, collect(dependencies))
causify(distr::Distribution) = causify(() -> rand(distr))
function causify(resolver, dependencies::CausalVariable...) 
    T = Base.promote_op(resolver, eltype.(dependencies)...)
    causify(resolver, T === Union{} ? Any : T, dependencies...)
end

"""
    getvalue(causalvar::CausalVariable)

Returns the value that is wrapped within the causalvar.
"""
getvalue(causalvar::CausalVariable) = @cases causalvar.value begin 
    Unknown => error(ValueUnknownError, " Can't get the value of an unknown value! Perhaps call resolve!(your_variable) first. The variable you attempted to get the value of was $causalvar")
    Known(x) => x
end

"""
    setvalue!(causalvar::CausalVariable{T}, value::T)

Sets the value that is wrapped within the causalvar. `value` must be of type `T` where `T` is the eltype of `causalvar`. 
"""
function setvalue!(causalvar::CausalVariable{T}, value) where T
    causalvar.value = Known{T}(convert(T, value))
    return causalvar
end

"""
    isknown(causalvar)

`true` is the causalvar has a known value (i.e. has been previously sampled). `false` otherwise.
""" 
isknown(causalvar::CausalVariable) = @cases causalvar.value begin
    Unknown => false 
    Known(x) => true
end

"""
    isunknown(causalvar)

`true` is the causalvar has an unknown value (i.e. has not been previously sampled). `false` otherwise.
"""
isunknown(causalvar::CausalVariable) = !isknown(causalvar)

"""
    setunknown!(causalvar)

Sets the value of the causal variable back to `Unknown`.
"""
function setunknown!(causalvar)
    causalvar.value = Unknown
    return causalvar
end

"""
    dependson(parent, child)

Checks where the parent depends on the child, recursively. If it doesn't depend, then obviously changing the `child` is not going to change `parent`. 
"""
dependson(parent::CausalVariable, child::CausalVariable) = isparent(parent, child)

"""
    isindependent(x, y)

Checks whether the two variables `x` and `y` are independent. This is recursive in the sense that it will check for all dependents of both variables. 
"""
function isindependent(x::CausalVariable, y::CausalVariable)
    dependencies = Base.IdSet{CausalVariable}()
    for dependency in preorder(x)
        push!(dependencies, dependency)
    end
    return !any(y -> y ∈ dependencies, preorder(y))
end

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
function resolve!(causalvar::CausalVariable)
    if isknown(causalvar) return getvalue(causalvar) end
    for child in postorder(causalvar; connector = (parent, child) -> isunknown(child))
        values = getvalue.(child.dependencies)
        setvalue!(child, child.resolver(values...))
    end 
    return getvalue(causalvar)
end
resolve!(causalvar::CausalVariable...) = resolve!.(causalvar)

"""
    refresh!(causalvar::CausalVariable...)

This makes the `CausalVariable` forget its current sample so you can resample the CausalVariable. 
Makes each of the `causalvar`s supplied `Unknown` and **recursively** does this for all children. 
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
refresh!(causalvar::CausalVariable...) = refresh!.(causalvar)

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

xs, ys = simulate!(5, x, y) # xs = 5 fresh samples of x, ys = 5 fresh samples of y; those samples are consistent in each row

@assert all(xs .^ 2 .== ys) # every value in xs squared equals the corresponding value in ys

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
function simulate!(intervention_function!, causalvar::CausalVariable...)
    refresh!(causalvar...)
    intervention_function!()
    return resolve!(causalvar...)
end
simulate!(causalvar::CausalVariable...) = simulate!(() -> (), causalvar...)

function simulate!(intervention_function!, n::Int, causalvar::CausalVariable...)
    k = length(causalvar)
    columns = ntuple(j -> Vector{eltype(causalvar[j])}(undef, n), k)
    for i in 1:n
        row = simulate!(intervention_function!, causalvar...)
        if k == 1
            columns[1][i] = row
        else
            for j in 1:k
                columns[j][i] = row[j]
            end
        end
    end
    return k == 1 ? columns[1] : columns
end
simulate!(n::Int, causalvar::CausalVariable...) = simulate!(() -> (), n, causalvar...)

"""
    simulate([intervention_function::Function, n::Int, ]causalvar::CausalVariable...)

Same as `simulate!` but will first check if your variables are known. If already known, it will error. 
This starts and leaves your variables in an unknown state. 

If you encounter errors, try calling `refresh!` before running this. 
"""
function simulate(intervention_function!, causalvar::CausalVariable...)
    if isanyknown(causalvar...) 
        error(ValueAlreadyKnownError, "You cannot call `simulate` on variables with known values. Instead call `simulate!` or `refresh!` your variables first. CausalVariable: $causalvar")
    end 
    intervention_function!()
    values = resolve!(causalvar...)
    refresh!(causalvar...)
    return values
end
simulate(causalvar::CausalVariable...) = simulate(() -> (), causalvar...)

function simulate(intervention_function!, n::Int, causalvar::CausalVariable...)
    if isanyknown(causalvar...)
        error(ValueAlreadyKnownError, "You cannot call `simulate` on variables with known values. Instead call `simulate!` or `refresh!` your variables first. CausalVariable: $causalvar")
    end
    result = simulate!(intervention_function!, n, causalvar...)
    refresh!(causalvar...)
    return result
end
simulate(n::Int, causalvar::CausalVariable...) = simulate(() -> (), n, causalvar...)

"""
    invalidate!(parent::CausalVariable, child::CausalVariable)

Sets the parent, and the child, and all variables on all pathways between them, to be `Unknown`.
This effectively invalidates the values in upstream variables which are dependent on the `child`, but limited to the scope of the dependencies of the `parent`. 
"""
function invalidate!(parent::CausalVariable, child::CausalVariable)
    for trace in findtraces(child, parent)
        for t in (trace[1:n] for n in 1:length(trace))
            setunknown!(pluck(parent, t))
        end 
    end 
    return parent
end

"""
    given(x::CausalVariable{T}, y::CausalVariable{<:Union{Bool, Missing}})

Creates a sampleable CausalVariable which represents the event `x` | `y`. 
This extends the doman of `x` into Union{T, Missing}, and enables rejection sampling. 
"""
given(x::CausalVariable, y::CausalVariable{<:Union{Bool, Missing}}) = causify((x,y) -> y === true ? x : missing, x, y)
Base.:|(x::CausalVariable, y::CausalVariable{<:Union{Bool, Missing}}) = given(x, y)

# Include the @causify macro
include(joinpath(@__DIR__, "CausifyMacro.jl"))

end  # module Causifyxion



