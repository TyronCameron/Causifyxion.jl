
"""
    _causals(t::Tuple)

The `CausalVariable`s in `t`, selected by tuple recursion so the result is type-inferrable.
"""
@inline _causals(t::Tuple{}) = ()
@inline _causals(t::Tuple) = _causals_first(first(t), Base.tail(t))
@inline _causals_first(x::AbstractCausalVariable, rest::Tuple) = (x, _causals(rest)...)
@inline _causals_first(::Any, rest::Tuple) = _causals(rest)

"""
    _merge_args(deps::Tuple, args::Tuple)

Rebuilds `deps`, replacing each `CausalVariable` with the next resolved value from `args`, by tuple recursion so the result is type-inferrable.
"""
@inline _merge_args(::Tuple{}, ::Tuple{}) = ()
@inline _merge_args(deps::Tuple, args::Tuple) = _merge_first(first(deps), Base.tail(deps), args)
@inline _merge_first(::AbstractCausalVariable, rest::Tuple, args::Tuple) = (first(args), _merge_args(rest, Base.tail(args))...)
@inline _merge_first(d, rest::Tuple, args::Tuple) = (d, _merge_args(rest, args)...)

_causify_impl(f::F, deps::Tuple, ::Tuple{}) where {F<:Function} = f(deps...)
_causify_impl(f::F, deps::Tuple, causals::Tuple) where {F<:Function} =
    causify((args...) -> f(_merge_args(deps, args)...), causals...)

_causify_all(f::F, deps...) where {F<:Function} = _causify_impl(f, deps, _causals(deps))
_causify_all_constants(f::F, deps...) where {F<:Function} =
    causify((args...) -> f(_merge_args(deps, args)...), _causals(deps)...)

"""
    @causify([settings..., ] expr)

This wraps normal Julia expressions inside a `causify()` function, and is the most convenient way to create causal variables.
This macro does not work for Distributions, for which you must use `causify()`.
The resulting `CausalVariable` is fully type-inferred at the call site.

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
@assert x isa CausalVariable && x.dependson == (a,)
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
z = 10

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

@causify :constants begin 
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
    settings, expr = _settings_and_expr(args...)
    new_expr = _causify(expr, settings)
    return esc(new_expr) 
end 

function _causify(expr, settings)
    expr isa Expr && expr.head == :block &&
        return _causify_block(expr, settings)
    expr isa Expr && expr.head == :(=) &&
        return _causify_assignment(expr, settings)
    return _causify_expr(expr, settings)
end

"""
    _causify_expr(expr, settings)

Wraps `expr` in a `causify` call depending on every symbol it contains.
"""
function _causify_expr(expr, settings)
    if !(expr isa Expr) && :constants ∉ settings return expr end
    sym_tuple = Expr(:tuple, filter(e -> e isa Symbol && occursin(r"^[a-zA-Z_]", string(e)), collect(leaves(expr)))...)
    target = :constants in settings ? _causify_all_constants : _causify_all
    return :($target($sym_tuple -> $expr, $sym_tuple...))
end

"""
    _causify_assignment(expr, settings)

Causifies the right-hand side of an assignment, keeping the assignment itself.
"""
function _causify_assignment(expr, settings)
    args = _causify(expr.args[2], settings)
    return :($(expr.args[1]) = $args)
end

"""
    _causify_block(expr, settings)

Causifies the assignments, nested blocks and final expression of a block, passing every other statement through.
"""
function _causify_block(expr, settings)
    new_exprs = []
    for (i,e) in enumerate(expr.args)
        is_valid_expression = e isa Expr && 
            (e.head == :(=) || e.head == :block || i == length(expr.args))
        if is_valid_expression
            push!(new_exprs, _causify(e, settings))
        else
            push!(new_exprs, e)
        end 
    end
    return Expr(:block, new_exprs...)
end

"""
    _settings_and_expr(args...)

Splits the arguments of `@causify` into its settings (symbols such as `constants`) and the expression to causify.
"""
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

