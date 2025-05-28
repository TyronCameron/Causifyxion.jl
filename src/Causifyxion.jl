"""
Causifyxion is a library creating and sampling from causally-related random variables.
"""
# module Causifyxion
# using Distributions, Taproots, ForwardDiff, QuadGK
# using MacroTools: @capture

# include("/home/tyronc/Nextcloud/Projects/packages/Taproots.jl/Taproots.jl/src/Taproots.jl")
include(joinpath(dirname(dirname(dirname(@__DIR__))), "Taproots.jl/Taproots.jl/src/Taproots.jl"))
using .Taproots

using SumTypes, Distributions

export getvalue, setvalue!, 
    isknown, isunknown,
    dependson, 
    rand!, reset!, randandreset!, nrand!,
    causify, @causify

@sum_type Possible{T} begin
    Unknown
    Known{T}(::T)
end 

"""
    CausalVariable{T}

A mutable struct, and the main struct that this package provides. 
A CausalVariable is just a wrapper around a mechanism of sampling that variable. Create one using `causify`.
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
    causify(rand::Function, dependencies::CausalVariable...)

z = causify(T, x, z) do x, z 
    x + z 
end 
"""
causify(rand::Function, ::Type{T}, dependson::CausalVariable...) where T = CausalVariable{T}(Unknown, rand, collect(dependson))
causify(distr::Distribution) = causify(() -> rand(distr), eltype(distr))
causify(rand::Function, dependson::CausalVariable...) = causify(rand, Union{Base.return_types(rand, eltype.(dependson))...}, dependson...)

"""
    getvalue(causalvariable)
"""
function getvalue(causalvariable::CausalVariable) 
    @cases causalvariable.value begin 
        Unknown => error("Can't get the value of an unknown causal variable! Perhaps call rand!(your_variable) first.")
        Known(x) => x
    end 
end

"""
    isknown(causalvariable)
""" 
function isknown(causalvariable::CausalVariable)
    @cases causalvariable.value begin
        Unknown => false 
        Known(x) => true
    end
end

isunknown(causalvariable::CausalVariable) = !isknown(causalvariable)

"""
    setvalue!(causalvariable, value)
"""
function setvalue!(causalvariable, value)
    causalvariable.value = Known(value)
    return causalvariable
end

function setunknown!(causalvariable)
    causalvariable.value = Unknown
    return causalvariable
end

"""
    rand!(rv...)
"""
function rand!(rv::CausalVariable)
    if isknown(rv) return getvalue(rv) end
    for child in postorder(rv; connector = isunknown)
        values = getvalue.(child.dependson)
        setvalue!(child, child.rand(values...))
    end 
    return getvalue(rv)
end

"""
    reset!(rv::CausalVariable...)
"""
function reset!(rv::CausalVariable)
    for child in postorder(rv)
        setunknown!(child)
    end 
    return rv
end

"""
    randandreset!(rv::CausalVariable...)
"""
function randandreset!(rv::CausalVariable)
    val = rand!(rv)
    reset!(rv)
    return val
end

for func in (:rand!, :reset!, :randandreset!)
    @eval $func(rv...) = ($func).([rv...])
end

"""
    nrand!(rv::CausalVariable...; n = 20)
"""
nrand!(rv::CausalVariable...; n = 20) = reduce(hcat, 1:n .|> x -> randandreset!.(rv))'


"""
    dependson(parent, child)

"""
dependson(parent::CausalVariable, child::CausalVariable) = isparent(parent, child)

macro collect_causal_variables(expr)
    syms = leaves(expr)
    quoted_vec = Expr(:vect, syms...)
    _results = gensym(:results)
    _val = gensym(:val)
    quote
        $_results = CausalVariable[]
        for $_val in $quoted_vec 
            $_val isa CausalVariable && push!($_results, $_val)
        end 
        $_results
    end |> esc
end

macro causify(expr)
    _causal_variables = gensym(:causal_variables)
    quote 
        $_causal_variables = @collect_causal_variables $expr
        causify($_causal_variables...) do 

        end 
    end 
end 

# The following rules apply
    # 1) x = @causify expr 
        # If expr resolves to a Distribution ... 
            # return causify(expr)
        # Else simply walks the expr, and any symbols of type CausalVariable go into the dependson tuple. Once done: 
        # quote 
            # causify($dependson...) do $dependson... 
                # $expr
            # end
        # end
    # 2) @causify x = expr 
        # Same thing as x = @causify expr 
    # 3) Can include begin ... end statements, such as 
        # @causify begin 
            # x = 1
            # y = 3 
            # z = begin 
                # ... 
            # end 
        # end 
        # If no assignment on the final return, that should also be wrapped in a CausalVariable
        # That basically puts a @causify before every assignment statement
    # 4) If settings are provided, use them first, regardless of the above rules 
            # @causify :noconstants begin 
                # ... 
            # end 


# function safe_rv_check(x)
#     try
#         eval(x) isa CausalVariable
#     catch
#         false
#     end
# end

# macro causify(expr)

#     _expr     = gensym(:expr)
#     _fexpr    = gensym(:fexpr)
#     _rvs      = gensym(:rvs)
#     _f        = gensym(:f)

#     return quote
#         local $(_expr)  = $(Meta.quot(expr))
#         local $(_fexpr) = leafmap(x -> safe_rv_check(x) ? :(rand!($x)) : x, $(_expr))
#         local $(_rvs)   = Iterators.filter(x -> safe_rv_check(x), leaves($(_expr)))
#         local $(_f)     = () -> eval($(_fexpr))
#         CausalVariable($(_f)(), true, $(_f), eval.($(_rvs)))
#     end |> esc

# end


x = causify(Normal(0, 1))
eltype(x)
y = causify(x) do x
    x^2
end 

y
x
rand!(y)



# filter(x -> :($(esc(x) isa CausalVariable)), leaves(:(x + y)) |> collect)
# map(x -> :($(esc(x))), leaves(:(x + y)) |> collect)

# function _unwrap_causal_variable(expr)
#     if expr isa Symbol
#         return :(_getvalue($(esc(expr))))
#     elseif expr isa Expr && expr.head == :call
#         return Expr(:call, expr.args[1], map(_unwrap_causal_variable, expr.args[2:end])...)
#     else
#         return expr
#     end
# end

# macro setknown!(exs...)
#     return quote (x -> begin
#         for ex in $exs
#             @capture(ex, ls__)
#             for l in ls
#                 @capture(l, before_ = after_) &&
#                 setknown!(eval(before), eval(after))
#             end
#         end
#     end)(nothing) end |> esc
# end

# using Plots, CausalVariables
# theme(:juno, grid = false)
# x = @rv rand(Normal(1,1))
# y = @rv rand(Normal(1,1))
# z = @rv x*y
# a = @rv z^2 + x

# plottree(
#     a,
#     title = "Plot of random variable a",
#     names = ["A" "Z" "X" "X" "Y"]
# )

# end  # module Causifyxion