module RandomVariables
push!(LOAD_PATH, @__DIR__)
using Distributions, DataFrames, Trees
using ForwardDiff, QuadGK
using MacroTools: @capture
export RandomVariable, rv, @rv, rand!, reset!, randandreset!, setknown!, nrand!, dependson

mutable struct RandomVariable{T}
    value::T
    isknown::Bool
    rand::Function
    dependson::Vector{Any} # to account for Vector{RandomVariable{<:T}} and []
end

rv(d::Distribution) = RandomVariable(rand(d), true, function() rand(d) end, [])
Trees.children(rv::RandomVariable) = rv.dependson .|> x -> x.x
Trees.printnode(rv::RandomVariable{<:Number}) = round(rv.value, digits = 2)
dependson(x::RandomVariable, y::RandomVariable) = isaparent(x, y)

function safeRVcheck(x)
    try
        eval(x) isa RandomVariable
    catch
        false
    end
end
macro rv(expr)
    return quote (x -> begin
        expr = :($$(Meta.quot(expr)))
        fexpr = $leafmap!(x -> safeRVcheck(x) ? :(rand!($x)) : x, expr)
        rvs = filter(x -> safeRVcheck(x), unique($leaves(expr)))
        f = function() eval(fexpr) end
        value = f()
        RandomVariable{typeof(value)}(value, true, f, Ref.(eval.(rvs)))
    end)(nothing) end |> esc
end

macro rvs(exs...)
    return quote for ex in $exs
        @capture(ex, ls__)
        for l in ls
            @capture(l, before_ = after_) ?
            quote $before = @rv $after end |> eval :
            eval(l)
        end
    end end |> esc
end

function rand!(rv::RandomVariable)
    if rv.isknown return rv.value end
    rv.isknown = true
    return rv.value = rv.rand()
end

function reset!(rv::RandomVariable)
    rv.isknown = false
    if !isempty(rv.dependson) reset!.(rv.dependson .|> x -> x.x) end
end

function randandreset!(rv::RandomVariable...)
    val = rand!(rv...)
    reset!(rv...)
    return val
end

function setknown!(rv::RandomVariable, val)
    rv.isknown = true
    rv.value = val
end

macro setknown!(exs...)
    return quote (x -> begin
        for ex in $exs
            @capture(ex, ls__)
            for l in ls
                @capture(l, before_ = after_) &&
                setknown!(eval(before), eval(after))
            end
        end
    end)(nothing) end |> esc
end

function nrand!(rv::RandomVariable...; n = 20)
    return DataFrame(reduce(hcat, 1:n .|> x -> randandreset!(rv...))', :auto)
end

for func in (:rand!, :reset!)
    @eval $func(rv...) = ($func).([rv...])
end

using Plots, RandomVariables
theme(:juno, grid = false)
x = @rv rand(Normal(1,1))
y = @rv rand(Normal(1,1))
z = @rv x*y
a = @rv z^2 + x

plottree(
    a,
    title = "Plot of random variable a",
    names = ["A" "Z" "X" "X" "Y"]
)


# function assigncause(f, start, stop; r = t -> [(start .+ (stop .- start) .* t)...])
#     grad(t) = ForwardDiff.gradient(f, r(t)) .* ForwardDiff.derivative(r, t)
#     val, ok = quadgk(grad, 0, 1, rtol = 1e-8)
#     if ok > 1e-8 @warn "Accuracy not met" end
#     return val
# end
#
# function rv_to_func(rv::RandomVariable)
#     return function(x)
#         @assert length(x) == length(rv.dependson) "Need a different number of parameters" # important in case they put in a scalar x
#         setknown!.(rv.dependson .|> x -> x.x, x)
#         rv.isknown = false
#         return randandreset!(rv)
#     end
# end
#
# start = (0,-π/2)
# stop = (π/4,-π/4)
# f(x,y) = sin(x)*cos(y)
# f_tup(x) = f(x...)
# assigncause(f_tup, start, stop)
#
# x = @rv rand(Normal(1,1))
# y = @rv rand(Normal(1,1))
# z = @rv x*y
#
# ReverseDiff.gradient(foo, (0:0.5:10, 0:20))
# foo = (x,y) -> sum(x .* y)
#
#
# using ReverseDiff
#
# ReverseDiff.gradient((x,y) -> Float64(x)^2 * y, [2,4])
# ForwardDiff.derivative(x -> Float64(Real(x))^2, 2)
#
# fff((9,3))
# fff = rv_to_func(z)
# typeof(fff)
# ForwardDiff.gradient(fff, [start...])
#
# gradient(fff, start)
#
# assigncause(f_tup, start, stop)
#
# nrand!(x,y,z,a)
#
# @setknown! x,y,z,a .= (1,7,1,4)
#
# function foo(x; n = 100)
#     return n*x
# end
#
#
# assigncause(rv::RandomVariable, start, stop; r = t -> [(start .+ (stop .- start) .* t)...]) = assigncause(rv_to_func(rv), start, stop; r = r)
#
# assigncause(z, (1,3), (0,1))
#
# ff = rv_to_func(z)
# ff([20,400])
# r = t -> [(start .+ (stop .- start) .* t)...]
# start, stop = (1,3), (0,1)
# r(0)
# ForwardDiff.gradient(ff, r(0)) .* ForwardDiff.derivative(r, 0)
#
# setknown!.(z.dependson .|> x -> x.x, (2,5))
# x.value
# y.value

end  # module RandomVariables