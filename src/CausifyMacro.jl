
# Helpers to create a CausalVariable from every symbol 

_get_and_incr(itr, state) = (itr[state], state + 1)

function merge_tuples(dependson, args)
    args_state = 1
    map(dependson) do d
        if !(d isa CausalVariable) return d end 
        r, args_state = _get_and_incr(args, args_state)
        r
    end 
end 

function _causify_all(rand::Function, dependson...; settings = Set{Symbol}()) 
    causals = filter(x -> x isa CausalVariable, dependson)
    if :constants ∉ settings && isempty(causals) return rand(dependson...) end 
    return causify(
        (args...) -> rand(merge_tuples(dependson, args)...),
        causals...
    )
end 

function _assigned_variable_symbols(expr)
    assigned_expressions = filter(e -> e.head == :(=), collect(preorder(expr)))
end 

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
macro causify(args...)
    settings, expr = _settings_and_expr(args...)
    new_expr = _causify(expr, settings)
    return esc(new_expr) 
end 

# Helper
function _causify(expr, settings)
    expr isa Expr && expr.head == :block &&
        return _causify_block(expr, settings)
    expr isa Expr && expr.head == :(=) &&
        return _causify_assignment(expr, settings)
    return _causify_expr(expr, settings)
end

# Rule 1: Causify expressions 
function _causify_expr(expr, settings)
    if !(expr isa Expr) && :constants ∉ settings return expr end 
    sym_tuple = Expr(:tuple, filter(e -> e isa Symbol && occursin(r"^[a-zA-Z_]", string(e)), collect(leaves(expr)))...)
    quote 
        Base.invokelatest($_causify_all, $sym_tuple -> $expr, $sym_tuple...; settings = $settings)
    end
end 

# Rule 2: Allow assignment statements through
function _causify_assignment(expr, settings)
    args = _causify(expr.args[2], settings)
    return :($(expr.args[1]) = $args)
end

# Rule 3: Allow blocks of code through
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

# Rule 4: Separate out symbols / flags
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

