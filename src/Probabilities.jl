using Random: AbstractRNG
using Distributions: DiscreteNonParametric
import Distributions: cdf, pdf, logpdf, quantile, support, probs, insupport

"""
    EmpiricalMeasure{T}

A finite set of distinct values of type `T`, each carrying a weight. Values are compared with `isequal` and `hash` only,
so `T` can be anything: numbers, symbols, tuples, or your own types.

The two concrete measures are `Tally` (integer counts) and `EmpiricalDistribution` (probabilities that sum to one).
Both support `map`, `marginal`, `given` / `|` and `product` / `⊗`.
"""
abstract type EmpiricalMeasure{T} end

"""
    Tally{T}

The distinct observations in a sample, with how many times each was seen. Create one with `tally`.
Call a tally on a value to get its count.
"""
struct Tally{T} <: EmpiricalMeasure{T}
    values::Vector{T}
    counts::Vector{Int}
    index::Dict{T, Int}
end

"""
    EmpiricalDistribution{T}

A discrete probability distribution over the distinct values of a sample. Create one with `distribution`.
Call a distribution on a value to get its probability mass.
"""
struct EmpiricalDistribution{T} <: EmpiricalMeasure{T}
    values::Vector{T}
    probabilities::Vector{Float64}
    index::Dict{T, Int}
end

_weights(t::Tally) = t.counts
_weights(d::EmpiricalDistribution) = d.probabilities
_entries(m::EmpiricalMeasure) = zip(m.values, _weights(m))

function _accumulate(values::AbstractVector{T}, weights::AbstractVector{W}) where {T, W}
    index = Dict{T, Int}()
    distinct, totals = T[], W[]
    for (value, weight) in zip(values, weights)
        i = get!(index, value) do
            push!(distinct, value)
            push!(totals, zero(W))
            length(distinct)
        end
        totals[i] += weight
    end
    return distinct, totals, index
end

_rebuild(::Tally, values, weights) = Tally(_accumulate(values, weights)...)
function _rebuild(::EmpiricalDistribution, values, weights)
    distinct, totals, index = _accumulate(values, weights)
    mass = sum(totals; init = 0.0)
    mass > 0 || throw(ArgumentError("cannot normalise a distribution with no mass"))
    return EmpiricalDistribution(distinct, totals ./ mass, index)
end

"""
    tally(sample::AbstractVector)

Counts the distinct values of `sample`.

```julia
t = tally([:a, :b, :a])
t(:a) # 2
```
"""
tally(sample::AbstractVector) = Tally(_accumulate(sample, ones(Int, length(sample)))...)

"""
    distribution(sample::AbstractVector)
    distribution(columns::AbstractVector...)
    distribution(tally::Tally)
    distribution(n::Int, causalvars::AbstractCausalVariable...)

The empirical distribution of a sample. Several columns give the joint distribution of their rows, as tuples.
Given causal variables, it simulates `n` joint draws of them first.

```julia
x = causify(Bernoulli(0.5))
y = @causify !x
d = distribution(1_000, x, y)
d((true, false)) # ≈ 0.5
```
"""
distribution(t::Tally) = EmpiricalDistribution(t.values, t.counts ./ total(t), t.index)
distribution(sample::AbstractVector) = distribution(tally(sample))
distribution(columns::AbstractVector...) = distribution(collect(zip(columns...)))
distribution(columns::Tuple{Vararg{AbstractVector}}) = distribution(columns...)
distribution(n::Int, causalvars::AbstractCausalVariable...) = distribution(simulate(n, causalvars...))

"""
    total(measure::EmpiricalMeasure)

The total weight: the number of observations for a `Tally`, and `1` for an `EmpiricalDistribution`.
"""
total(m::EmpiricalMeasure) = sum(_weights(m))

"""
    mass(measure::EmpiricalMeasure, value)

The weight of `value`: its count in a `Tally`, or its probability in an `EmpiricalDistribution`. Zero if never seen.
Calling the measure, `measure(value)`, does the same.
"""
function mass(m::EmpiricalMeasure, value)
    i = get(m.index, value, 0)
    return i == 0 ? zero(eltype(_weights(m))) : _weights(m)[i]
end
(m::EmpiricalMeasure)(value) = mass(m, value)

"""
    map(f, measure::EmpiricalMeasure)

The pushforward of `measure` through `f`: the measure of `f(X)`. Values with the same image have their weights added.
This is how to marginalise (see `marginal`), relabel, or discretise continuous values:

```julia
d = distribution(randn(1_000))
map(x -> round(x; digits = 1), d)
```
"""
Base.map(f, m::EmpiricalMeasure) = _rebuild(m, map(f, m.values), _weights(m))

"""
    marginal(measure::EmpiricalMeasure, i)

The marginal measure of component `i` of each value (an index, a field name, or a tuple of them), via `map`.

```julia
d = distribution([1, 1, 2], [:a, :b, :b])
marginal(d, 2) # :a => 1/3, :b => 2/3
```
"""
marginal(m::EmpiricalMeasure, i) = map(value -> value[i], m)
marginal(m::EmpiricalMeasure, i::Tuple) = map(value -> map(j -> value[j], i), m)

"""
    given(measure::EmpiricalMeasure, event)
    measure | event

Restricts `measure` to the values where `event(value)` is true.
A `Tally` keeps the counts of those values; an `EmpiricalDistribution` is renormalised to give the conditional distribution.

```julia
d = distribution([1, 1, 2, 2], [:a, :b, :b, :b])
marginal(d | (s -> s[1] == 2), 2) # P(Y | X = 2): :b => 1.0
```
"""
function given(m::EmpiricalMeasure, event)
    kept = findall(event, m.values)
    return _rebuild(m, m.values[kept], _weights(m)[kept])
end
Base.:|(m::EmpiricalMeasure, event) = given(m, event)

"""
    product(measure::EmpiricalMeasure, kernel)
    product(x::EmpiricalMeasure, y::EmpiricalMeasure)
    x ⊗ y

The product rule. `kernel(x)` returns the measure of `Y` given `X = x`, and the result is the joint measure of `(x, y)`
with weight `measure(x) * kernel(x)(y)`. When `Y` is a measure rather than a kernel, `X` and `Y` are independent.

```julia
d = distribution([1, 1, 2, 2], [:a, :b, :b, :b])
px = marginal(d, 1)
d == product(px, x -> marginal(d | (s -> s[1] == x), 2)) # true, up to ordering of the support
```
"""
function product(m::EmpiricalMeasure, kernel)
    joint = [((x, y), wx * wy) for (x, wx) in _entries(m) for (y, wy) in _entries(kernel(x))]
    return _rebuild(m, first.(joint), last.(joint))
end
product(x::EmpiricalMeasure, y::EmpiricalMeasure) = product(x, _ -> y)
const ⊗ = product

function Base.:(==)(a::EmpiricalMeasure, b::EmpiricalMeasure)
    typeof(a) == typeof(b) || return false
    length(a.values) == length(b.values) || return false
    return all(((value, weight),) -> mass(b, value) == weight, _entries(a))
end
Base.isapprox(a::EmpiricalMeasure, b::EmpiricalMeasure; kwargs...) =
    issetequal(keys(a.index), keys(b.index)) && all(v -> isapprox(mass(a, v), mass(b, v); kwargs...), a.values)

function Base.show(io::IO, m::M) where {M <: EmpiricalMeasure}
    print(io, nameof(M), "{", eltype(m), "}(", length(m.values), " values)")
end

Base.eltype(::Type{<:EmpiricalMeasure{T}}) where T = T

support(m::EmpiricalMeasure) = m.values
probs(m::EmpiricalMeasure) = _weights(m) ./ total(m)
insupport(m::EmpiricalMeasure, value) = haskey(m.index, value)
pdf(d::EmpiricalDistribution, value) = mass(d, value)
logpdf(d::EmpiricalDistribution, value) = log(pdf(d, value))

function Base.rand(rng::AbstractRNG, m::EmpiricalMeasure)
    threshold = rand(rng) * total(m)
    i = searchsortedfirst(cumsum(_weights(m)), threshold)
    return m.values[min(i, length(m.values))]
end

Base.convert(::Type{DiscreteNonParametric}, d::EmpiricalDistribution) = DiscreteNonParametric(d.values, d.probabilities)

_isbelow(value, s) = value <= s
_isbelow(value::Tuple, s::Tuple) = all(map(<=, value, s))

"""
    cdf(d::EmpiricalDistribution, s)

The probability that a value is at most `s`, componentwise for tuples. This needs `<=` on the values.
"""
function cdf(d::EmpiricalDistribution{T}, s) where T
    T <: Tuple && length(s) != fieldcount(T) && throw(DimensionMismatch("expected a $(fieldcount(T))-tuple, got $(length(s))"))
    return sum(((value, p),) -> _isbelow(value, s) ? p : 0.0, _entries(d); init = 0.0)
end

"""
    quantile(d::EmpiricalDistribution, p::Real)

The smallest value whose cumulative probability reaches `p`. This needs the values to be sortable.
"""
function quantile(d::EmpiricalDistribution, p::Real)
    0 <= p <= 1 || throw(DomainError(p, "p must be in [0, 1]"))
    order = sortperm(d.values)
    i = searchsortedfirst(cumsum(d.probabilities[order]), p)
    return d.values[order[min(i, length(order))]]
end
Base.minimum(m::EmpiricalMeasure) = minimum(m.values)
Base.maximum(m::EmpiricalMeasure) = maximum(m.values)

"""
    copula(samples::Tuple{Vararg{AbstractVector}})

Transforms each sample by its own empirical `cdf`, and returns the joint distribution of the transformed rows along with the marginals.
"""
function copula(samples::Tuple{Vararg{AbstractVector}})
    marginals = distribution.(samples)
    cdfsample = map(marginals, samples) do marginal, sample
        map(s -> cdf(marginal, s), sample)
    end
    return distribution(cdfsample...), marginals
end
