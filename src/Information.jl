using Random: AbstractRNG, default_rng, shuffle
import StatsBase: crossentropy, entropy, kldivergence

_crossentropy(p::EmpiricalDistribution, q) = -sum(((s, ps),) -> ps * log(q(s)), _entries(p); init = 0.0)
_kldivergence(p::EmpiricalDistribution, q) = _crossentropy(p, s -> q(s) / p(s))

"""
    crossentropy(p::EmpiricalMeasure, q::EmpiricalMeasure)

The cross-entropy `-Σ p(s) log q(s)` in nats, summed over the support of `p`.
It is `Inf` when `q` gives zero mass to a value `p` has seen. A `Tally` is normalised first.

Every other information measure here is a special case of it.
"""
crossentropy(p::EmpiricalMeasure, q::EmpiricalMeasure) = _crossentropy(distribution(p), distribution(q))

"""
    entropy(p::EmpiricalMeasure)

The Shannon entropy `crossentropy(p, p)` in nats.
"""
entropy(p::EmpiricalMeasure) = crossentropy(p, p)

"""
    kldivergence(p::EmpiricalMeasure, q::EmpiricalMeasure)

The Kullback-Leibler divergence `Σ p(s) log(p(s) / q(s))` in nats. It is `Inf` when `q` gives zero mass to a value `p` has seen.
"""
kldivergence(p::EmpiricalMeasure, q::EmpiricalMeasure) = _kldivergence(distribution(p), distribution(q))

"""
    mutualinfo(p::EmpiricalMeasure)
    mutualinfo(xs, ys[, zs])

The mutual information in nats of a joint measure over `(x, y)` tuples: the divergence of `p` from the product of its marginals.
Over `(x, y, z)` tuples it is the conditional mutual information `I(X;Y|Z)`, comparing `p` with `p(x|z) p(y|z) p(z)`.
Given columns, it builds their joint `distribution` first.

Values can be of any type. For a multivariate `X`, use a column of tuples.
This is the plug-in estimate, which is biased upwards by roughly `(|X|-1)(|Y|-1) / 2n` for `n` observations.
Use `independencetest` to judge whether an estimate is meaningfully above zero.
Continuous values are almost never repeated, so discretise them first, e.g. `round.(xs; digits = 1)`.

```julia
x = causify(Bernoulli(0.5))
y = @causify x ⊻ rand(Bernoulli(0.1))
mutualinfo(distribution(10_000, x, y)) # ≈ log(2) - entropy of a Bernoulli(0.1) ≈ 0.37
```
"""
function mutualinfo(p::EmpiricalMeasure{<:Tuple{Any, Any}})
    d = distribution(p)
    px, py = marginal(d, 1), marginal(d, 2)
    return _kldivergence(d, s -> px(s[1]) * py(s[2]))
end
function mutualinfo(p::EmpiricalMeasure{<:Tuple{Any, Any, Any}})
    d = distribution(p)
    pxz, pyz, pz = marginal(d, (1, 3)), marginal(d, (2, 3)), marginal(d, 3)
    return _kldivergence(d, s -> pxz((s[1], s[3])) * pyz((s[2], s[3])) / pz(s[3]))
end
mutualinfo(xs::AbstractVector, ys::AbstractVector) = mutualinfo(distribution(xs, ys))
mutualinfo(xs::AbstractVector, ys::AbstractVector, zs::AbstractVector) = mutualinfo(distribution(xs, ys, zs))
mutualinfo(xs::AbstractVector, ys::AbstractVector, ::Nothing) = mutualinfo(xs, ys)

_groups(::Nothing, xs) = (collect(eachindex(xs)),)
function _groups(zs::AbstractVector, _)
    groups = Dict{eltype(zs), Vector{Int}}()
    for (i, z) in pairs(zs)
        push!(get!(groups, z, Int[]), i)
    end
    return values(groups)
end

function _shuffle_within(rng::AbstractRNG, xs, groups)
    shuffled = copy(xs)
    for group in groups
        shuffled[group] = xs[shuffle(rng, group)]
    end
    return shuffled
end

"""
    independencetest(xs, ys[, zs]; permutations = 200, rng = Random.default_rng())

Tests whether `xs` and `ys` are independent (or conditionally independent given `zs`) with a permutation test on `mutualinfo`.
Returns `(; estimate, pvalue)`. A small `pvalue` is evidence of dependence.

`xs` is shuffled within each value of `zs` (or freely without `zs`), which breaks any link to `ys` while keeping its relationship with `zs`.
This also accounts for the upward bias of the plug-in estimate.

```julia
x = causify(Bernoulli(0.5))
y = @causify x ⊻ rand(Bernoulli(0.1))
xs, ys = simulate(500, x, y)
independencetest(xs, ys).pvalue # ≈ 0.005: dependent
```
"""
function independencetest(xs::AbstractVector, ys::AbstractVector, zs = nothing; permutations::Int = 200, rng::AbstractRNG = default_rng())
    estimate = mutualinfo(xs, ys, zs)
    groups = _groups(zs, xs)
    exceed = count(1:permutations) do _
        mutualinfo(_shuffle_within(rng, xs, groups), ys, zs) >= estimate
    end
    return (; estimate, pvalue = (1 + exceed) / (1 + permutations))
end
