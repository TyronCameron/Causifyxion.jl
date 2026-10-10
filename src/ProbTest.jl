
# Experimental code to see where this package is going next

using Causifyxion
using Taproots
using Distributions
using Random

# ═══════════════════════════════════════════════════════════════════════════════
# i.i.d.
# ═══════════════════════════════════════════════════════════════════════════════
 
# Main idea here is that we create n independent versions of the causalvar 
# which populate a vector of n independent samples 

# Another name might be Population 
mutable struct IIDCausalVariable{T}
    samplers::Vector{CausalVariable{T}}
    n::Int
    values::Possible{Vector{T}}
end 

iid(n::Int, x::CausalVariable; threads = Threads.nthreads()) = IIDCausalVariable(map(_ -> deepcopy(x), 1:threads), n, Unknown)
function resolve!(x::IIDCausalVariable{T}) where T
    if isknown(x) return getvalue(x) end
    pool = Channel{CausalVariable{T}}(x.samplers)
    results = Vector{Float64}(undef, x.n)
    @sync for range in Iterators.partition(1:n, 1_000)
        Threads.@spawn begin
            y = take!(pool)
            try
                for i in range
                    out[i] = simulate!(y)
                end
            finally
                put!(pool, y)
            end
        end
    end
    setvalue!(x, results)
    return results
end
# Noticing that I will need an AbstractCausalVariable and this will need to inherit 

# ═══════════════════════════════════════════════════════════════════════════════
# Another thought 
# ═══════════════════════════════════════════════════════════════════════════════

# On the topic of creating new types of CausalVariable which inherit from AbstractCausalVariable
struct Resampler
    sample
    weights 
end 

# One option: 
# Temporarily swap in a Resampler inside a resolver to achieve importance sampling
# Basically, do rejection sampling with fewer rejections. 

# Originally I thought it may be necessary to make it inherit from AbstractCausalVariable 
# But now I am not too sure. 

# ═══════════════════════════════════════════════════════════════════════════════
# Collapse
# ═══════════════════════════════════════════════════════════════════════════════

# Build in a stochastic optimiser:
# Note that start and x may be different spaces altogether
# The idea is that S would actually be a vector of numbers 
# And then the loss function would use those parameters to get us something 
# Classic case: S = float, T = bool

function collapse(loss, start::S, x::CausalVariable{T})
    # samples x many times, finds some value y::T which optimises loss(y,x)
end 

using ForwardDiff
using Statistics
 
"""
    collapse(loss, x; steps = 2_000, batch = 64, pilot = 1_000)
 
Collapse a random variable to one value: the `y` that minimises the expected loss
E[loss(y, X)] over draws of `x`, i.e. the Bayes action. `loss(y, sample)` scores a single
draw. Draws that are `missing` (a failed `given`) are skipped.
 
- Floating-point or vector-of-floats `x`: stochastic gradient descent. Every step takes a
  fresh batch of draws and moves `y` against the gradient of the batch's average loss
  (Adam steps, scaled to the spread of `x`). The answer is the average of the second half
  of the path, which smooths out the noise. `loss` must be differentiable in `y`.
- Anything else (integers, booleans, categories, symbols…): every distinct value seen in a
  pilot run is a candidate, and the one with the lowest average loss wins. The result is
  then always a value `x` can actually take.
"""
function collapse(loss, x::CausalVariable; steps = 2_000, batch = 64, pilot = 1_000)
    samples = draws(x, pilot)
    isempty(samples) && error("Every draw was missing: the condition never held.")
    return optimise(loss, x, samples; steps, batch)
end
 
draws(x, n) = collect(skipmissing(simulate!(n, x)))
averageloss(loss, y, samples) = mean(loss(y, sample) for sample in samples)
 
# Scalar: optimise a 1-vector so scalars and vectors share one optimiser
function optimise(loss, x, samples::AbstractVector{<:AbstractFloat}; kw...)
    objective(v, batch) = averageloss(loss, only(v), batch)
    return only(descend(objective, x, [mean(samples)], [std(samples)]; kw...))
end
 
function optimise(loss, x, samples::AbstractVector{<:AbstractVector{<:AbstractFloat}}; kw...)
    objective(v, batch) = averageloss(loss, v, batch)
    spread = vec(std(reduce(hcat, samples); dims = 2))
    return descend(objective, x, mean(samples), spread; kw...)
end
 
# Discrete or non-numeric: exact search over the values actually seen
optimise(loss, x, samples; kw...) = argmin(y -> averageloss(loss, y, samples), unique(samples))
 
"""
Stochastic gradient descent with Adam steps. Each step's size is `rate × scale / √t`, so it
starts at a tenth of the spread of `x` and shrinks. That shrinking is what lets the noisy
gradients settle on an answer.
"""
function descend(objective, x, y, scale; steps, batch, rate = 0.1, β₁ = 0.9, β₂ = 0.999, ϵ = 1e-8)
    y = float.(y)
    scale = map(s -> s > 0 ? s : one(s), scale) # a constant coordinate still needs a step size
    m = zero(y)
    v = zero(y)
    average = zero(y)
    for t in 1:steps
        batchdraws = draws(x, batch)
        isempty(batchdraws) && continue
        g = ForwardDiff.gradient(z -> objective(z, batchdraws), y)
        @. m = β₁ * m + (1 - β₁) * g
        @. v = β₂ * v + (1 - β₂) * g^2
        @. y -= rate * scale / sqrt(t) * (m / (1 - β₁^t)) / (sqrt(v / (1 - β₂^t)) + ϵ)
        if t > steps ÷ 2
            average .+= (y .- average) ./ (t - steps ÷ 2) # running mean of the second half
        end
    end
    return average
end

# ═══════════════════════════════════════════════════════════════════════════════
# Distance and Divergence
# ═══════════════════════════════════════════════════════════════════════════════

# Definitely going to add KL divergence into here 
# Mutual information 
# Each of the distances: sum(|x - y|) and sum(|x - y|^2)
# And the obvious: sup(|x - y|)
# Wasserstein distance 
# This needs much more thinking. 

# ═══════════════════════════════════════════════════════════════════════════════
# Testing
# ═══════════════════════════════════════════════════════════════════════════════
 
x1 = causify(Bernoulli(0.1))
x2 = causify(Bernoulli(0.1))
x3 = causify(Bernoulli(0.1))

a1 = causify(Bernoulli(0.8))
a2 = causify(Bernoulli(0.8))
a3 = causify(Bernoulli(0.8))

s = causify(Bernoulli(0.5))

x = @causify x1 + x2 + x3 + s
a = @causify a1 + a2 + a3 + s

y = @causify x^2 + a^2

resolve!(y)

distribution(y; n = 10000)

distribution(y | @causify(!s), n = 10000)

!(1 > 2)
!(true)

# function normalise!(dict)
#     s = sum(values(dict))
#     for (key, value) in pairs(dict)
#         dict[key] = value / s
#     end 
#     return dict
# end 