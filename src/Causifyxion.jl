
"""
Causifyxion is a library for creating causally-related variables, and sampling from them.
"""
module Causifyxion

using Taproots
using SumTypes
using Distributions: Distribution

export CausalVariable,
    ValueUnknownError, getvalue, setvalue!, setunknown!,
    isknown, isunknown,
    isanyknown, isnothingknown, dependson, isindependent,
    ValueAlreadyKnownError,
    resolve!, refresh!, simulate!, simulate, invalidate!,
    causify, @causify, given,
    isexclusive, isexhaustive, isbasis,
    # degree,
    replicate, Population, population
    # Tally, tally, total, EmpiricalDistribution, distribution,
    # cdf, mass, pdf, logpdf, support, probs, insupport, quantile, copula

abstract type AbstractCausalVariable end 

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
struct ValueUnknownError <: Exception
    msg::String
end
Base.showerror(io::IO, e::ValueUnknownError) = print(io, e.msg)

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
mutable struct CausalVariable{T,F,S<:Tuple} <: AbstractCausalVariable
    value::Base.RefValue{Possible{T}}
    resolver::F
    dependencies::Vector{AbstractCausalVariable}
end
Taproots.children(causalvar::AbstractCausalVariable) = causalvar.dependencies
Base.copy(cv::CausalVariable{T,F,S}) where {T,F,S} = CausalVariable{T,F,S}(Ref(cv.value[]), cv.resolver, copy(cv.dependencies))
Taproots.setchildren!(causalvar::AbstractCausalVariable, children) = (causalvar.dependencies = children; causalvar)
Base.eltype(::CausalVariable{T}) where {T} = T
function Base.show(io::IO, causalvar::CausalVariable) 
    type = eltype(causalvar)
    value = @cases causalvar.value[] begin
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
causify(resolver, ::Type{T}, dependencies::NTuple{N,AbstractCausalVariable}) where {T,N} = 
    CausalVariable{T, typeof(resolver), Tuple{map(eltype, dependencies)...}}(Ref{Possible{T}}(Unknown), resolver, collect(AbstractCausalVariable, dependencies))
causify(resolver, ::Type{T}, dependencies::AbstractCausalVariable...) where T = causify(resolver, T, dependencies)

causify(distr::Distribution) = causify(() -> rand(distr))

function causify(resolver, dependencies::NTuple{N,AbstractCausalVariable}) where N
    T = Base.promote_op(resolver, eltype.(dependencies)...)
    causify(resolver, T === Union{} ? Any : T, dependencies)
end
causify(resolver, dependencies::AbstractCausalVariable...) = causify(resolver, dependencies)

"""
    getvalue(causalvar::CausalVariable)

Returns the value that is wrapped within the causalvar.
"""
getvalue(causalvar::AbstractCausalVariable) = @cases causalvar.value[] begin 
    Unknown => throw(ValueUnknownError("Can't get the value of an unknown value! Perhaps call resolve!(your_variable) first. The variable you attempted to get the value of was $causalvar"))
    Known(x) => x
end

"""
    setvalue!(causalvar::CausalVariable{T}, value::T)

Sets the value that is wrapped within the causalvar. `value` must be of type `T` where `T` is the eltype of `causalvar`. 
"""
function setvalue!(causalvar::AbstractCausalVariable, value)
    T = eltype(causalvar)
    causalvar.value[] = Known{T}(convert(T, value))
    return causalvar
end

"""
    isknown(causalvar)

`true` is the causalvar has a known value (i.e. has been previously sampled). `false` otherwise.
""" 
isknown(causalvar::AbstractCausalVariable) = @cases causalvar.value[] begin
    Unknown => false 
    Known(x) => true
end

"""
    isunknown(causalvar)

`true` is the causalvar has an unknown value (i.e. has not been previously sampled). `false` otherwise.
"""
isunknown(causalvar::AbstractCausalVariable) = !isknown(causalvar)

"""
    setunknown!(causalvar)

Sets the value of the causal variable back to `Unknown`.
"""
function setunknown!(causalvar::AbstractCausalVariable)
    causalvar.value[] = Unknown
    return causalvar
end

"""
    dependson(parent, child)

Checks where the parent depends on the child, recursively. If it doesn't depend, then obviously changing the `child` is not going to change `parent`. 
"""
dependson(parent::AbstractCausalVariable, child::AbstractCausalVariable) = isparent(parent, child)

"""
    isindependent(x, y)

Checks whether the two variables `x` and `y` are independent. This is recursive in the sense that it will check for all dependents of both variables. 
"""
function isindependent(x::AbstractCausalVariable, y::AbstractCausalVariable)
    dependencies = Set()
    for dependency in preorder(x)
        push!(dependencies, dependency)
    end
    return !any(y -> y ∈ dependencies, preorder(y))
end

"""
    isanyknown(causalvar::CausalVariable...)

Checks whether `causalvar` is known, or any of its dependencies are known. 
"""
isanyknown(causalvar::AbstractCausalVariable) = any(isknown, postorder(causalvar))
isanyknown(causalvar::NTuple{N,AbstractCausalVariable}) where N = any(isanyknown, causalvar)
isanyknown(causalvar::AbstractCausalVariable...) = isanyknown(causalvar)

"""
    isnothingknown(causalvar::CausalVariable...)

Checks whether `causalvar` is unknown, and all of its dependencies are unknown. 
"""
isnothingknown(causalvar::NTuple{N,AbstractCausalVariable}) where N = !isanyknown(causalvar)
isnothingknown(causalvar::AbstractCausalVariable...) = isnothingknown(causalvar)

"""
    ValueAlreadyKnownError

You cannot simulate a CausalVariable if some parts of it are already known.
"""
struct ValueAlreadyKnownError <: Exception
    msg::String
end
Base.showerror(io::IO, e::ValueAlreadyKnownError) = print(io, e.msg)

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
function resolve!(causalvar::AbstractCausalVariable)
    if isknown(causalvar) return getvalue(causalvar) end
    for node in postorder(causalvar; connector = (parent, child) -> isunknown(child))
        _resolve_single_node!(node)
    end 
    return getvalue(causalvar)
end

function _resolve_single_node!(causalvar::CausalVariable{T,F,S}) where {T,F,S}
    deps = causalvar.dependencies
    values = ntuple(i -> getvalue(deps[i], fieldtype(S, i)), Val(fieldcount(S)))
    causalvar.value[] = Known{T}(convert(T, causalvar.resolver(values...)))
    return causalvar
end
getvalue(causalvar::AbstractCausalVariable, ::Type{T}) where {T} = @cases (causalvar.value::Base.RefValue{Possible{T}})[] begin
    Unknown => getvalue(causalvar)
    Known(x) => x
end
resolve!(causalvar::Tuple{AbstractCausalVariable}) = resolve!(causalvar[1])
resolve!(causalvar::NTuple{N,AbstractCausalVariable}) where N = resolve!.(causalvar)
resolve!(causalvar::AbstractCausalVariable...) = resolve!(causalvar)

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
function refresh!(causal_variable::AbstractCausalVariable)
    for child in postorder(causal_variable)
        setunknown!(child)
    end 
    return causal_variable
end
refresh!(causalvar::Tuple{AbstractCausalVariable}) = refresh!(causalvar[1])
refresh!(causalvar::NTuple{N,AbstractCausalVariable}) where N = refresh!.(causalvar)
refresh!(causalvar::AbstractCausalVariable...) = refresh!(causalvar)

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
function simulate!(intervention_function!, causalvar::NTuple{N,AbstractCausalVariable}) where N
    refresh!(causalvar)
    intervention_function!()
    return resolve!(causalvar)
end
simulate!(intervention_function!, causalvar::AbstractCausalVariable...) = simulate!(intervention_function!, causalvar)
simulate!(causalvar::NTuple{N,AbstractCausalVariable}) where N = simulate!(() -> (), causalvar)
simulate!(causalvar::AbstractCausalVariable...) = simulate!(causalvar)

function simulate!(intervention_function!, n::Int, causalvar::NTuple{N,AbstractCausalVariable}) where N
    k = length(causalvar)
    columns = ntuple(j -> Vector{eltype(causalvar[j])}(undef, n), k)
    for i in 1:n
        row = simulate!(intervention_function!, causalvar)
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
simulate!(intervention_function!, n::Int, causalvar::AbstractCausalVariable...) = simulate!(intervention_function!, n, causalvar)
simulate!(n::Int, causalvar::NTuple{N,AbstractCausalVariable}) where N = simulate!(() -> (), n, causalvar)
simulate!(n::Int, causalvar::AbstractCausalVariable...) = simulate!(n, causalvar)

"""
    simulate([intervention_function::Function, n::Int, ]causalvar::CausalVariable...)

Same as `simulate!` but will first check if your variables are known. If already known, it will error. 
This starts and leaves your variables in an unknown state. 

If you encounter errors, try calling `refresh!` before running this. 
"""
function simulate(intervention_function!, causalvar::NTuple{N,AbstractCausalVariable}) where N
    if isanyknown(causalvar)
        throw(ValueAlreadyKnownError("You cannot call `simulate` on variables with known values. Instead call `simulate!` or `refresh!` your variables first. CausalVariable: $causalvar"))
    end
    intervention_function!()
    values = resolve!(causalvar)
    refresh!(causalvar)
    return values
end
simulate(intervention_function!, causalvar::AbstractCausalVariable...) = simulate(intervention_function!, causalvar)
simulate(causalvar::NTuple{N,AbstractCausalVariable}) where N = simulate(() -> (), causalvar)
simulate(causalvar::AbstractCausalVariable...) = simulate(causalvar)

function simulate(intervention_function!, n::Int, causalvar::NTuple{N,AbstractCausalVariable}) where N
    if isanyknown(causalvar)
        throw(ValueAlreadyKnownError("You cannot call `simulate` on variables with known values. Instead call `simulate!` or `refresh!` your variables first. CausalVariable: $causalvar"))
    end
    result = simulate!(intervention_function!, n, causalvar)
    refresh!(causalvar)
    return result
end
simulate(intervention_function!, n::Int, causalvar::AbstractCausalVariable...) = simulate(intervention_function!, n, causalvar)
simulate(n::Int, causalvar::NTuple{N,AbstractCausalVariable}) where N = simulate(() -> (), n, causalvar)
simulate(n::Int, causalvar::AbstractCausalVariable...) = simulate(n, causalvar)

"""
    invalidate!(parent::CausalVariable, child::CausalVariable)

Sets the parent, and the child, and all variables on all pathways between them, to be `Unknown`.
This effectively invalidates the values in upstream variables which are dependent on the `child`, but limited to the scope of the dependencies of the `parent`. 
"""
function invalidate!(parent::AbstractCausalVariable, child::AbstractCausalVariable)
    for trace in findtraces(child, parent)
        for t in (trace[1:n] for n in 1:length(trace))
            setunknown!(pluck(parent, t))
        end 
    end 
    return setunknown!(parent)
end

"""
    replicate(causalvar::AbstractCausalVariable, keep::AbstractCausalVariable...)

Creates a fresh verison of the `causalvar`, recursively copying each value beneath it, except the variables you have specified, which are shared with the originals. 
"""
function replicate(causalvar::AbstractCausalVariable, keep::NTuple{N,AbstractCausalVariable}) where N
    ignored = Set(keep)
    causalvar in ignored && return causalvar
    copies = Dict{AbstractCausalVariable, AbstractCausalVariable}(s => s for s in keep)
    for node in postorder(causalvar; connector = (_, child) -> child ∉ ignored)
        copies[node] = setchildren!(
            setunknown!(copy(node)), 
            map(c -> copies[c], children(node))
        )
    end
    return copies[causalvar]
end
replicate(causalvar::AbstractCausalVariable, keep::AbstractCausalVariable...) = replicate(causalvar, keep)
replicate(n::Int, causalvar::AbstractCausalVariable, keep::NTuple{N,AbstractCausalVariable}) where N = map(_ -> replicate(causalvar, keep), 1:n)
replicate(n::Int, causalvar::AbstractCausalVariable, keep::AbstractCausalVariable...) = map(_ -> replicate(causalvar, keep...), 1:n)

"""
    degree(causalvariable...)

Returns the sum of the in-degree of each variable in the dependencies of the variables above. 
"""
degree(causalvariable...) = sum(node -> length(children(node)), preorder(causalvariable...))

"""
    isexclusive(response, covariates)

No covariate is a dependency of another. 
These variables can share ancestors or be correlated. They cannot, however, mediate the effect one another on the response. 
"""
function isexclusive(response::AbstractCausalVariable, covariates::NTuple{N,AbstractCausalVariable}) where N
    separators = Set(covariates)
    length(separators) == N || return false
    reached = 0
    for covariate in preorder(response; connector = (parent, _) -> parent ∉ separators)
        covariate ∉ separators && continue 
        any(node -> node ∈ separators, Iterators.drop(preorder(covariate), 1)) && return false
        reached += 1
    end
    return reached == N
end
isexclusive(response::AbstractCausalVariable, covariates::AbstractCausalVariable...) = isexclusive(response, covariates)

""" 
    isexhaustive(response, covariates)

Checks whether the set of covariates has all dependencies covered; i.e. there is no path leading to a leaf node which is not covered 
(that is, no unexplained path). 
"""
function isexhaustive(response::AbstractCausalVariable, covariates::NTuple{N,AbstractCausalVariable}) where N
    separators = Set(covariates)
    response ∈ separators && return true
    walk = Iterators.drop(preorder(response; connector = (_, child) -> child ∉ separators), 1)
    return !any(isleaf, walk)
end 
isexhaustive(response::AbstractCausalVariable, covariates::AbstractCausalVariable...) = isexhaustive(response, covariates)

"""
    isbasis(response, covariates)

Checks whether the list of covariates is a complete and non-confounding description of the response variable.
"""
isbasis(response::AbstractCausalVariable, covariates::NTuple{N,AbstractCausalVariable}) where N = 
    isexclusive(response, covariates) && isexhaustive(response, covariates) 
isbasis(response::AbstractCausalVariable, covariates::AbstractCausalVariable...) = isbasis(response, covariates)

"""
    given(x::CausalVariable{T}, y::CausalVariable{<:Union{Bool, Missing}})

Creates a sampleable CausalVariable which represents the event `x` | `y`. 
This extends the doman of `x` into Union{T, Missing}, and enables rejection sampling. 
"""
given(x::CausalVariable, y::CausalVariable{<:Union{Bool, Missing}}) = causify((x,y) -> y === true ? x : missing, x, y)
Base.:|(x::CausalVariable, y::CausalVariable{<:Union{Bool, Missing}}) = given(x, y)

include(joinpath(@__DIR__, "CausifyMacro.jl"))
include(joinpath(@__DIR__, "Populations.jl"))
# include(joinpath(@__DIR__, "Probabilities.jl"))

end  # module Causifyxion



