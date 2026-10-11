# ---------------------------------------------------------------------------
# Tally
# ---------------------------------------------------------------------------

"""
    Tally{T}

A set of unique observations and counts associated. Useful as a step to obtain empirical probabilities. 
Requires `isless` to be defined over T. 
"""
struct Tally{T}
    values::Vector{T}
    counts::Vector{Int}
end

function tally(sample::AbstractVector{T}) where T
    values, counts = T[], Int[]
    for s in sort(sample)
        if !isempty(values) && s == last(values)
            counts[end] += 1
        else
            push!(values, s)
            push!(counts, 1)
        end
    end
    return Tally(values, counts)
end

function (tally::Tally)(s)
    i = searchsorted(tally.values, s)
    isempty(i) && return 0
    return tally.counts[first(i)]
end

total(tally::Tally) = sum(tally.counts)

# ---------------------------------------------------------------------------
# Heuristics
# ---------------------------------------------------------------------------

# """
#     is_continuous_heuristic(tally::Tally; n = 1000, p = 0.995)

# A heuristic to determine continuity of a sample. It returns true when the sample is large and almost every observation is a distinct value.
# """
# is_continuous_heuristic(tally::Tally; n = 1000, p = 0.995) =
#     total(tally) > n && length(tally.values) > p * total(tally)

# is_strictly_increasing(vec) = all(vec[begin:end-1] .< vec[begin+1:end])
# is_strictly_decreasing(vec) = all(vec[begin:end-1] .> vec[begin+1:end])
# is_unbounded_upwards_heuristic(sample; n = 1000, p = 0.995, k = 3, ϵ = 1) = 
#     length(sample) > n && is_strictly_increasing(map(a -> max(first(sample, a)), n/k:n/k:n))
# is_unbounded_downwards_heuristic(sample; n = 1000, p = 0.995, k = 3, ϵ = 1) = 
#     length(sample) > n && is_strictly_decreasing(map(a -> min(first(sample, a)), n/k:n/k:n))
# is_unbounded_heuristic(sample; n = 1000, p = 0.995, k = 3, ϵ = 1) = 
    # is_unbounded_upwards_heuristic(sample) && is_unbounded_downwards_heuristic(sample)

# ---------------------------------------------------------------------------
# Empirical Probability Mass
# ---------------------------------------------------------------------------
using Random: AbstractRNG
using Distributions: DiscreteNonParametric
import Distributions: cdf, pdf, logpdf, quantile, support, probs, insupport

const MultivariateValue = Union{Tuple, AbstractVector}

struct EmpiricalDistribution{T}
    values::Vector{T}
    cumulative_probabilities::Vector{Float64}
    total::Int
end

function Base.show(io::IO, distr::EmpiricalDistribution{T}) where T
    print(io, "EmpiricalDistribution{", T, "}(", length(distr.values), " values, ", distr.total, " observations)")
end

Base.broadcastable(distr::EmpiricalDistribution) = Ref(distr)
Base.eltype(::Type{EmpiricalDistribution{T}}) where T = T
Base.convert(::Type{DiscreteNonParametric}, d::EmpiricalDistribution) = 
    DiscreteNonParametric(d.values, diff([0.0; d.cumulative_probabilities]))

function distribution(tally::Tally{T}) where T 
    t = total(tally)
    EmpiricalDistribution{T}(tally.values, cumsum(tally.counts) ./ t, t)
end 
distribution(sample::AbstractVector) = distribution(tally(sample))
distribution(columns::AbstractVector...) = distribution(collect(zip(columns...)))
distribution(columns::Tuple{Vararg{AbstractVector}}) = distribution(collect(zip(columns...)))

function cdf(distr::EmpiricalDistribution, s)
    i = searchsortedlast(distr.values, s)
    return i == 0 ? 0.0 : distr.cumulative_probabilities[i]
end

function cdf(distr::EmpiricalDistribution{T}, s::MultivariateValue) where {T <: MultivariateValue}
    length(s) == fieldcount(T) || throw(DimensionMismatch("expected a $(fieldcount(T))-tuple, got $(length(s))"))
    n = 0
    prev = 0
    for (v, c) in zip(distr.values, distr.cumulative_probabilities)
        k = round(Int, c * distr.total)
        all(map(<=, v, s)) && (n += k - prev)
        prev = k
    end
    return n / distr.total
end

function mass(distr::EmpiricalDistribution, s)
    i = searchsortedfirst(distr.values, s)
    (i <= length(distr.values) && isequal(distr.values[i], s)) || return 0.0
    return i == 1 ? distr.cumulative_probabilities[1] : distr.cumulative_probabilities[i] - distr.cumulative_probabilities[i - 1]
end

pdf(distr::EmpiricalDistribution, s) = mass(distr, s)
logpdf(distr::EmpiricalDistribution, s) = log(pdf(distr, s))
function Base.rand(rng::AbstractRNG, distr::EmpiricalDistribution) 
    i = searchsortedfirst(distr.cumulative_probabilities, rand(rng))
    distr.values[min(i, length(distr.values))]
end 
Base.minimum(distr::EmpiricalDistribution) = first(support(distr))
Base.maximum(distr::EmpiricalDistribution) = last(support(distr))
support(distr::EmpiricalDistribution) = distr.values
probs(distr::EmpiricalDistribution) = diff([0.0; distr.cumulative_probabilities])
tally(distr::EmpiricalDistribution) = Tally(distr.values, round.(Int, probs(distr) .* distr.total))
insupport(distr::EmpiricalDistribution, s) = mass(distr, s) > 0

(distr::EmpiricalDistribution)(s) = cdf(distr, s)

function quantile(distr::EmpiricalDistribution{T}, p::Real) where T
    0 <= p <= 1 || throw(DomainError(p, "p must be in [0, 1]"))
    return support(distr)[min(searchsortedfirst(distr.cumulative_probabilities, p), length(distr.cumulative_probabilities))]
end

function copula(samples::Tuple{Vararg{AbstractVector}})
    marginals = distribution.(samples)
    cdfsample = map(marginals, samples) do cdf, sample
        cdf.(sample)
    end 
    return distribution(cdfsample...), marginals 
end
