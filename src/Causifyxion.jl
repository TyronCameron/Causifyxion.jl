
# """
# Causifyxion is a library creating and sampling from causally-related random variables.
# """
# module Causifyxion

using Taproots
using SumTypes
using Distributions: Distribution

export CausalVariable,
    ValueUnknownError, getvalue, setvalue!, 
    isknown, isunknown,
    dependson, 
    rand!, reset!, resetandrand!, nrand!,
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
abstract type ValueUnknownError <: Exception end 

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

get_and_incr(itr, state) where T = (itr[state], state + 1)
function merge_tuples(dependson, args)
    args_state = 1
    map(dependson) do d
        if !(d isa CausalVariable) return d end 
        r, args_state = get_and_incr(args, args_state)
        r
    end 
end 
function _causify_all(rand::Function, dependson...) 
    causals = filter(x -> x isa CausalVariable, dependson)
    return causify(
        (args...) -> rand(merge_tuples(dependson, args)...),
        causals...
    )
end 


"""
    getvalue(causalvariable::CausalVariable)

Returns the value that is wrapped within the causalvariable.
"""
getvalue(causalvariable::CausalVariable) = @cases causalvariable.value begin 
    Unknown => error(ValueUnknownError, " Can't get the value of an unknown value! Perhaps call rand!(your_variable) first.")
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
    rand!(causalvariables...)

Samples each of the `causalvariables` supplied and returns the value of those answers. 
If the variable value is already known, it returns that known value.

Example: 

```julia
x = causify(Uniform(0,1))
first_sample = rand!(x)
second_sample = rand!(x)

@assert first_sample == second_sample # note that rand! is not a completely fresh sample. It keeps known values around until you set the CausalVariable to `Unknown`. 
```

`rand!` recursively modifies all CausalVariables beneath it, by design, because it samples them all. 
"""
function rand!(causalvariable::CausalVariable)
    if isknown(causalvariable) return getvalue(causalvariable) end
    for child in postorder(causalvariable; connector = isunknown)
        values = getvalue.(child.dependson)
        setvalue!(child, Base.invokelatest(child.rand, (values...)))
    end 
    return getvalue(causalvariable)
end

"""
    reset!(rv::CausalVariable...)

In short, this makes the `CausalVariable` forget its current sample so you can resample the CausalVariable. 
Makes each of the `causalvariables` supplied `Unknown` and **recursively** does this for all children. 
To do this non-recursively, rather use `setunknown!`. 

Example: 

```julia
x = causify(Uniform(0,1))
y = @causify x^2

first_sample = rand!(y)

@assert isknown(x) # This value is sampled through y
@assert isknown(y) # This value is sampled directly 

reset!(y)

@assert isunknown(x) # This value was reset through y
@assert isunknown(y) # This value was reset directly 
```
"""
function reset!(rv::CausalVariable)
    for child in postorder(rv)
        setunknown!(child)
    end 
    return rv
end

"""
    resetandrand!([intervention_function::Function, ]rv::CausalVariable...)

Get an absolutely fresh sample of your variables. 

Examples:

```julia
x = causify(Uniform(0,1))
y = @causify x^2
fresh_sample1 = resetandrand!(y)
fresh_sample2 = resetandrand!(y)

@assert fresh_sample1 != fresh_sample2 # these are 100% fresh samples

rigged_value = resetandrand!(y) do
    setvalue!(x, 0.5)
end 

@assert rigged_value == 0.25 
```
"""
function resetandrand!(intervention_function!::Function, causalvariable::CausalVariable...)
    reset!(causalvariable...)
    intervention_function!()
    return rand!(causalvariable...)
end
resetandrand!(causalvariable::CausalVariable...) = resetandrand!(() -> (), causalvariable...)

for func in (:rand!, :reset!)
    @eval $func(rv...) = ($func).([rv...])
end

"""
    nrand!([intervention_function!::Function, ]rv::CausalVariable...; n = 5)

Get `n` absolutely fresh samples of your variables. Super handy if you want to sample lots of stuff. 

Examples:

```julia
x = causify(Uniform(0,1))
y = @causify x^2 # define y as x^2

mat = nrand!(x, y) # first column = 5 fresh samples of x, second column = 5 fresh samples of y; those samples are consistent in each row

@assert all(mat[:,1] .^ 2 .== mat[:,2]) # every value in column 1 squared equals every value in column 2

rigged_matrix = nrand!(x, y) do
    setvalue!(x, 0.5)
end 

@assert all(rigged_matrix[:,1] .== 0.5)
@assert all(rigged_matrix[:,2] .== 0.25)

# and then if you want...
using DataFrames
df = DataFrame(rigged_matrix, [:x, :y])
```
"""
nrand!(intervention_function!::Function, causalvariable::CausalVariable...; n = 5) = reduce(vcat, (permutedims(resetandrand!(intervention_function!, collect(causalvariable)...)) for _ in 1:n))
nrand!(causalvariable::CausalVariable...; n = 5) = reduce(vcat, (permutedims(resetandrand!(collect(causalvariable)...)) for _ in 1:n))

"""
    dependson(parent, child)

Checks where the parent depends on the child, recursively. If it doesn't depend, then obviously changing the `child` is not going to change `parent`. 
"""
dependson(parent::CausalVariable, child::CausalVariable) = isparent(parent, child)


"""
    @causify([settings..., ] expr)

This wraps normal Julia expressions inside a `causify()` function, and is the most convenient way to create causal variables.
This macro does not work for Distributions, for which you must use `causify()`.
At the moment there may or may not be a heinous abomination of code making this work. 

```julia
u = @causify Uniform(0,1) # ❌ usually not going to do what you want (unless you are wanted to parameterise the distribution itself with causal variables)
u = causify(Uniform(0,1)) # ✅ much better
```

The following rules apply: 

# 1) You can causify expressions containing other CausalVariables

Example: 

```julia
a = causify(Normal(1,1))
b = 20
x = @causify a + b
@assert x isa CausalVariable && x.dependson = (a,)
```

This is equivalent to doing: 

```julia
x = causify(a) do a 
    a + b
end 
```

# 2) You can causify entire assignment expressions 

Example:

```julia
a = causify(Normal(1,1))
b = 20
@causify x = a + b
@assert x isa CausalVariable && x.dependson = (a,)
```

# 3) You can causify entire begin ... end blocks 

Example: 

```julia
x = causify(Normal(0, 1))
y = @causify x^2

@causify begin 
    a = x + y 
    b = x + z 
    c = 15
    d = 15 + 19 
    e = d + a
end 

@assert e isa CausalVariable
@assert !(d isa CausalVariable)
```

# 4) You can pass settings to the macro 

Example: 

```julia
x = causify(Normal(0, 1))
y = @causify x^2

@causify begin 
    a = x + y 
    b = x + z 
    c = 15
    d = 15 + 19 
    e = d + a
end 

@assert e isa CausalVariable
@assert d isa CausalVariable && eltype(d) <: Int
```
"""
macro causify(expr)
    @assert expr isa Symbol || (expr isa Expr && expr.head == :call) """Pls try again later"""
    sym_tuple = Expr(:tuple, filter(e -> e isa Symbol, collect(leaves(expr)))...)
    quote 
        causify_all($sym_tuple -> $expr, $sym_tuple...)
    end |> esc
end 
# macro causify(args...)
#     settings, expr = _settings_and_expr(args...)
#     if expr isa Expr && expr.head == :block 
#         new_expr = causify_block(expr, settings) |> esc
#     elseif expr isa Expr && expr.head == :(=) 
#         new_expr = causify_assignment(expr, settings) |> esc
#     elseif expr isa Expr 
#         new_expr = causify_expr(expr, settings)
#     else 
#         new_expr = expr 
#     end 
#     return new_expr
# end 

# function _settings_and_expr(args...)
#     settings = Set{Symbol}()
#     expr = args[end]
#     for arg in args
#         if arg isa Symbol push!(settings, arg) end 
#         if (arg isa QuoteNode && arg.value isa Symbol) push!(settings, arg.value) end 
#         if arg isa Expr 
#             expr = arg
#             break 
#         end 
#     end 
#     return settings, expr
# end 

# function causify_block(expr, settings; __module__ = @__MODULE__)
#     new_exprs = []
#     for (i,e) in enumerate(expr.args)
#         if !(e isa Expr) 
#             push!(new_exprs, e) 
#             continue
#         end 
#         if e.head == :(=) || i == length(expr.args)
#             push!(new_exprs, :($_causify(esc($e))))
#         end 
#     end 
#     return Expr(:block, new_exprs...)
# end 

# function causify_assignment(expr, settings; __module__ = @__MODULE__)
#     args = causify_expr(expr.args[2], settings; __module__ = __module__)
#     return :($(esc(expr.args[1])) = $args)
# end

# end  # module Causifyxion



