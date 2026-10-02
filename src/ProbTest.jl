
# Experimental code to see where this package is going next

using Causifyxion
using Taproots
using Distributions
using Random

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1
# ═══════════════════════════════════════════════════════════════════════════════

# Might need a better name & api 
# Take a new deepcopy of x, except don't deepcopy y,z. 
# One should ideally use taproots functionality for this -- possibly tapmap can just do this 
function fresh(x; keep = Set([y,z])) 
    for node in preorder(x; connector = (parent, child) -> child ∉ keep)

    end 
end 

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
# cdf
# ═══════════════════════════════════════════════════════════════════════════════

struct CDF{T}
    values::Vector{T}
    probability::Vector{Float64}
end 

tally(sample::Vector{T}) where T = foldl(sample, init = (T[], Int[])) do (values, counts), s
    i = searchsortedlast(values, s)
    if i > 0 && values[i] == s
        counts[i] += 1 
    else 
        insert!(values, i + 1, s)
        insert!(counts, i + 1, 1)
    end 
    return (values, counts)
end

normalise(v) = v ./ sum(v)

function cdf(sample)
    values, counts = tally(sample)
    CDF(values, cumsum(normalise(counts)))
end 

function (cdf::CDF{T})(s::T) where T
    i = searchsortedlast(cdf.values, s)
    return i > 0 ? cdf.probability[i] : 0
end

# c = cdf([1,1,1,1,2,3,34,4,4,4,4,4,5])
# c(0)

# using Plots

# plot(c.(0:35))

# And then the magic ... 
function selfcdf(x::CausalVariable; n = 1000)
    sample = simulate(n, x)
    c = cdf(sample)
    @causify(c(x))
end 

# Entire section needs better naming 

# Remember that 
# copula(xs) = joint(selfcdf.(xs))

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
# Categorical Distributions
# ═══════════════════════════════════════════════════════════════════════════════

# Before we begin here, a few notes ... 
# simulate(n, xs...) gives me the joint samples right away, and all I need to do is tally it up to get a categorical distribution 
# sort!(simulate(x, xs...)) and then gives me the marginals... which is basically tallying them up individually


"""
    OutcomeVariate
 
The variate form of a `CategoricalDistribution`. Each sample is one outcome (a single value,
or a tuple of values), not a number or an array. Distributions.jl already has non-array
variate forms (e.g. `CholeskyVariate`), so this follows that precedent.
"""
struct OutcomeVariate <: Distributions.VariateForm end
 
"""
    CategoricalDistribution{T}
 
A distribution over a finite set of outcomes of type `T`, stored most likely first.
 
It is a Distributions.jl `Distribution`, so `rand`, `pdf`, `logpdf`, `support` and `probs`
work, and `causify(d)` turns it back into a root variable.
"""
struct CategoricalDistribution{T} <: Distribution{OutcomeVariate,Distributions.Discrete}
    outcomes::Vector{T}
    probabilities::Vector{Float64}
end
 
"""Build from Dict(outcome ⇒ weight). Weights are normalised to sum to 1."""
function CategoricalDistribution(table::AbstractDict)
    entries = sort!(collect(table); by = last, rev = true)
    total = sum(last, entries)
    outcomes = [outcome for (outcome, _) in entries]
    probabilities = [weight / total for (_, weight) in entries]
    return CategoricalDistribution(outcomes, probabilities)
end
 
Base.eltype(::Type{CategoricalDistribution{T}}) where T = T
Distributions.support(d::CategoricalDistribution) = d.outcomes
Distributions.probs(d::CategoricalDistribution) = d.probabilities
 
function Distributions.pdf(d::CategoricalDistribution, outcome)
    i = findfirst(isequal(outcome), d.outcomes)
    return i === nothing ? 0.0 : d.probabilities[i]
end
Distributions.logpdf(d::CategoricalDistribution, outcome) = log(pdf(d, outcome))
 
Base.rand(rng::AbstractRNG, d::CategoricalDistribution) =
    d.outcomes[rand(rng, Categorical(d.probabilities))]
Base.rand(d::CategoricalDistribution, n::Int) = rand(Random.default_rng(), d, n)
function Base.rand(rng::AbstractRNG, d::CategoricalDistribution, n::Int)
    index = sampler(Categorical(d.probabilities))
    return [d.outcomes[rand(rng, index)] for _ in 1:n]
end
 
"""
    marginal(d, i)
 
From a joint over several targets, the distribution of the `i`th target alone.
"""
function marginal(d::CategoricalDistribution{<:Tuple}, i::Int)
    table = Dict{Any,Float64}()
    for (outcome, p) in zip(d.outcomes, d.probabilities)
        table[outcome[i]] = get(table, outcome[i], 0.0) + p
    end
    return CategoricalDistribution(table)
end
 
Base.show(io::IO, d::CategoricalDistribution) =
    print(io, "CategoricalDistribution(", length(d.outcomes), " outcomes)")
function Base.show(io::IO, ::MIME"text/plain", d::CategoricalDistribution)
    print(io, "CategoricalDistribution with ", length(d.outcomes), " outcomes:")
    shown = min(length(d.outcomes), 20)
    for i in 1:shown
        print(io, "\n  ", repr(d.outcomes[i]), " => ", round(d.probabilities[i]; digits = 4))
    end
    shown < length(d.outcomes) && print(io, "\n  ⋮")
end

# ═══════════════════════════════════════════════════════════════════════════════
# Distribution estimation
# ═══════════════════════════════════════════════════════════════════════════════
 

"""
    tally(samples)

Return a dictionary which is the frequency table of the samples. 
"""
tally(
    samples::AbstractVector{T}; 
    by = identity, 
    init = Dict{Base.promote_op(by, eltype(samples)), Int}()
) where T = foldl(samples; init) do dict, sample
    key = by(sample)
    dict[key] = get(dict, key, 0) + 1
    return dict
end

function atomic_simulate(x::CausalVariable, configuration; n = 1000)
    for (child, config) in zip(children(x), configuration)
        setvalue!(child, config)
    end 
    map(1:n) do _
        setunknown!(x)
        resolve!(x)
    end 
end 

normalise(counts) = (total = sum(values(counts)); Dict(k => c / total for (k, c) in counts))
atomic_distribution(x, configuration; n = 1000) = normalise(tally(atomic_simulate(x, configuration; n)))

function atomic_distributions(xs::CausalVariable...; n = 1000)
    distributions = Dict()
    for x in postorder(xs...)
        children_configs = (unique(Iterators.flatmap(keys, values(distributions[child]))) for child in children(x))
        configurations = Iterators.product(children_configs...)
        push!(distributions, x => Dict())
        for config in configurations 
            push!(distributions[x], config => atomic_distribution(x, config; n))
        end 
    end 
    return distributions
end 

_childvalues(node, outcome) = (value = IdDict(outcome); Tuple(value[child] for child in children(node)))
_conditional(distrs, node, outcome) = distrs[node][_childvalues(node, outcome)]
_chain(distrs, joint, node) = Dict(
    (outcome..., node => value) => p * q
    for (outcome, p) in joint
    for (value, q) in _conditional(distrs, node, outcome)
)

_targetvalues(value, (x,)::Tuple{CausalVariable}) = value[x]
_targetvalues(value, xs) = Tuple(value[x] for x in xs)
_marginal(joint, xs) = foldl(joint; init = Dict{Any,Float64}()) do result, (outcome, p)
    key = _targetvalues(IdDict(outcome), xs)
    result[key] = get(result, key, 0.0) + p
    return result
end

function distribution(xs::CausalVariable...; n = 1000)
    distrs = atomic_distributions(xs...; n)
    joint = foldl((joint, node) -> _chain(distrs, joint, node), postorder(xs...); init = Dict(() => 1.0))
    return CategoricalDistribution(_marginal(joint, xs))
end

# ═══════════════════════════════════════════════════════════════════════════════
# Copula estimation
# ═══════════════════════════════════════════════════════════════════════════════
 
"Each draw's rank, scaled into (0, 1). Ties are broken at random so discrete values still spread out."
pseudos(draws) = invperm(sortperm(collect(zip(draws, rand(length(draws)))))) ./ (length(draws) + 1)

"Empirical quantile: the draw at position u of the sorted draws."
quantile_of(sorted, u) = sorted[clamp(ceil(Int, u * length(sorted)), 1, length(sorted))]

"Checkerboard copula: which of k equal-mass bins each target fell in, tallied jointly."
function checkerboard(columns, k)
    bins = [ceil.(Int, k .* pseudos(column)) for column in columns]
    return CategoricalDistribution(tally(collect(zip(bins...))))
end

function copula_distribution(xs::CausalVariable...; n = 10_000, k = 10)
    draws = simulate!(n, xs...)
    draws = length(xs) == 1 ? (draws,) : draws
    return checkerboard(draws, k), sort.(collect.(draws))
end

"Sample: pick a cell, a uniform point inside it, then map each coordinate through its marginal."
function sample(copula, marginals, k)
    cell = rand(copula)
    u = (cell .- rand(length(cell))) ./ k
    return Tuple(quantile_of(m, ui) for (m, ui) in zip(marginals, u))
end



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