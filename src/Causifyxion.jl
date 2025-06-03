"""
Causifyxion is a library creating and sampling from causally-related random variables.
"""
module Causifyxion

using Taproots
using SumTypes
using Distributions: Distribution

export CausalVariable,
    ValueUnknownError, getvalue, setvalue!, 
    isknown, isunknown,
    dependson, 
    rand!, reset!, resetandrand!, nrand!,
    causify, @causify

@sum_type Possible{T} begin
    Unknown
    Known{T}(::T)
end 

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

abstract type ValueUnknownError <: Exception end 

"""
    getvalue(causalvariable::CausalVariable)

Returns the value that is wrapped within the causalvariable.
"""
function getvalue(causalvariable::CausalVariable) 
    @cases causalvariable.value begin 
        Unknown => error(ValueUnknownError, " Can't get the value of an unknown causal variable! Perhaps call rand!(your_variable) first.")
        Known(x) => x
    end 
end

"""
    setvalue!(causalvariable::CausalVariable{T}, value::T)

Sets the value that is wrapped within the causalvariable. `value` must be of type `T` where `T` is the eltype of `causalvariable`. 
"""
function setvalue!(causalvariable::CausalVariable{T}, value::T) where T
    causalvariable.value = Known{eltype(causalvariable)}(value)
    return causalvariable
end

"""
    isknown(causalvariable)

`true` is the causalvariable has a known value (i.e. has been previously sampled). `false` otherwise.
""" 
function isknown(causalvariable::CausalVariable)
    @cases causalvariable.value begin
        Unknown => false 
        Known(x) => true
    end
end

"""
    isknown(causalvariable)

`true` is the causalvariable has a known value (i.e. has been previously sampled). `false` otherwise.
"""
isunknown(causalvariable::CausalVariable) = !isknown(causalvariable)

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

@assert first_sample == second_sample # note that rand! is not a completely fresh sample. It keeps known values around. 
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

Makes each of the `causalvariables` supplied unknown and **recursively** does this for all children. 

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
macro causify(args...)
    _causify(args...; __module__ = esc(:(@__MODULE__)))
end 

# the map esc seems to cause problems at global scope 
# internally seems fine
# so don't export this one 
macro collect_causal_variables(expr)
    syms = leaves(expr) |> collect
    quoted_vec = Expr(:vect, map(s -> esc(s), syms)...)
    _syms = gensym(:syms)
    _results = gensym(:results)
    _sym = gensym(:sym)
    _val = gensym(:val)
    quote
        $_syms = Symbol[]
        $_results = CausalVariable[]
        for ($_sym, $_val) in zip($syms, $quoted_vec)
            if $_val isa CausalVariable 
                push!($_syms, $_sym)
                push!($_results, $_val)
            end 
        end 
        ($_syms, $_results)
    end |> esc
end

function _causify(args...; __module__ = @__MODULE__)
    settings, expr = _settings_and_expr(args...)
    if expr.head == :block 
        return _causify_block(expr, settings; __module__ = __module__)
    elseif expr.head == :(=) 
        return _causify_assignment(expr, settings; __module__ = __module__)
    elseif expr isa Expr 
        return _causify_expr(expr, settings; __module__ = __module__)
    else 
        return expr 
    end 
end 

function _causify_block(expr, settings; __module__ = @__MODULE__)
    new_exprs = []
    for e in expr.args
        if !(e isa Expr) 
            push!(new_exprs, e) 
            continue
        end 
        if e.head == :(=) 
            push!(new_exprs, _causify_assignment(e, settings; __module__ = __module__))
        elseif e isa Expr 
            push!(new_exprs, _causify_expr(e, settings; __module__ = __module__))
        end 
    end 
    return Expr(:block, new_exprs...)
end 

function _causify_assignment(expr, settings; __module__ = @__MODULE__)
    args = _causify_expr(expr.args[2], settings; __module__ = __module__)
    return :($(esc(expr.args[1])) = $args)
end

function _causify_expr(expr, settings; __module__ = @__MODULE__)
    println(settings)
    quote 
        syms, vals = @collect_causal_variables($expr)
        if isempty(syms) && :constants ∉ $settings
            $(esc(expr))
        else 
            local arg_tuple = Expr(:tuple, syms...)
            local func = Expr(:->, arg_tuple, $(Meta.quot(expr)))
            causify(Core.eval($(__module__), func), vals...)
        end 
    end 
end

function _settings_and_expr(args...)
    settings = Set{Symbol}()
    expr = args[end]
    for arg in args
        if arg isa Symbol push!(settings, arg) end 
        if (arg isa QuoteNode && arg.value isa Symbol) push!(settings, arg.value) end 
        if arg isa Expr 
            expr = arg
            break 
        end 
    end 
    return settings, expr
end 

end  # module Causifyxion