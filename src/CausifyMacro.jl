
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
    return _causify(expr, settings)
end 

# Helper
function _causify(expr, settings)
    if expr isa Expr && expr.head == :block 
        new_expr = causify_block(expr, settings) |> esc
    elseif expr isa Expr && expr.head == :(=) 
        new_expr = causify_assignment(expr, settings) |> esc
    elseif expr isa Expr 
        new_expr = causify_expr(expr, settings) |> esc
    else 
        new_expr = expr 
    end 
    return new_expr
end

# Rule 1: Causify expressions 
function causify_expr(expr, settings)
    sym_tuple = Expr(:tuple, filter(e -> e isa Symbol, collect(leaves(expr)))...)
    quote 
        $_causify_all($sym_tuple -> $expr, $sym_tuple...; settings = $settings)
    end
end 

# Rule 2: Allow assignment statements through
function causify_assignment(expr, settings)
    args = causify_expr(expr.args[2], settings)
    return :($(expr.args[1]) = $args)
end

# Rule 3: Allow blocks of code through
function causify_block(expr, settings)
    new_exprs = []
    for (i,e) in enumerate(expr.args)
        if !(e isa Expr) 
            push!(new_exprs, e) 
            continue
        end 
        if e.head == :(=) || i == length(expr.args)
            push!(new_exprs, :($_causify(esc($e), $settings)))
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

