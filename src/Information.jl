using Random: AbstractRNG, default_rng, randperm

"""
    Causifyxion.distance(a, b)

The metric used by the information estimators (`mutualinfo`, `shannonentropy`, `kldiv`, `independencetest`).

- `Real` values are compared with `abs(a - b)`, so they are treated as continuous (or ordinal).
- `Bool` values, and any other type, use the discrete metric: `0` if equal, `Inf` otherwise.
- Tuples and vectors use the maximum distance over their components.

Extend it to give your own type a continuous treatment:

```julia
Causifyxion.distance(a::MyType, b::MyType) = abs(a.position - b.position)
```
"""
distance(a::Real, b::Real) = Float64(abs(a - b))
distance(a::Bool, b::Bool) = a == b ? 0.0 : Inf
distance(a::Union{Tuple, AbstractVector}, b::Union{Tuple, AbstractVector}) =
    maximum(((p, q),) -> distance(p, q), zip(a, b); init = 0.0)
distance(a, b) = isequal(a, b) ? 0.0 : Inf

_distance(a::AbstractVector, i, b::AbstractVector, j) = distance(a[i], b[j])
_distance(a, i, b, j) = maximum(((p, q),) -> _distance(p, i, q, j), zip(a, b); init = 0.0)
_distance(::Nothing, i, ::Nothing, j) = 0.0
_distance(x, i, j) = _distance(x, i, x, j)

_length(column::AbstractVector) = length(column)
_length(columns) = length(first(columns))

_permute(column::AbstractVector, perm) = column[perm]
_permute(columns, perm) = map(column -> column[perm], columns)

function _digamma(m::Integer)
    m < 6 && return sum(j -> 1 / j, 1:m-1; init = 0.0) - Base.MathConstants.eulergamma
    return log(m) - 1 / 2m - 1 / 12m^2 + 1 / 120m^4
end

_count_within(distances, ρ, i) = count(j -> j != i && distances[j] <= ρ, eachindex(distances))

function _kth_smallest!(buffer, distances, k, i)
    copyto!(buffer, distances)
    buffer[i] = Inf
    return partialsort!(buffer, k)
end

function _check_neighbours(n, k)
    k >= 1 || throw(ArgumentError("k must be at least 1, got $k"))
    n > k || throw(ArgumentError("need more than k = $k observations, got $n"))
end

function _conditional_mutualinfo(x, y, z, k)
    n = _length(x)
    _check_neighbours(n, k)
    dxyz, dxz, dyz, dz, buffer = (Vector{Float64}(undef, n) for _ in 1:5)
    total = 0.0
    for i in 1:n
        for j in 1:n
            a, b, c = _distance(x, i, j), _distance(y, i, j), _distance(z, i, j)
            dxyz[j], dxz[j], dyz[j], dz[j] = max(a, b, c), max(a, c), max(b, c), c
        end
        ρ = _kth_smallest!(buffer, dxyz, k, i)
        total += _digamma(_count_within(dxyz, ρ, i)) - _digamma(_count_within(dxz, ρ, i)) -
            _digamma(_count_within(dyz, ρ, i)) + _digamma(_count_within(dz, ρ, i))
    end
    return total / n
end

"""
    mutualinfo(x, y[, z]; k = 3)

Estimates the mutual information `I(X;Y)` in nats from paired samples, or the conditional mutual information `I(X;Y|Z)` when `z` is given.

Each of `x`, `y` and `z` is a column (an `AbstractVector`), or a tuple / `NamedTuple` of columns for a multivariate variable.
This is the shape `simulate(n, ...)` returns, and the shape of `NamedTuple(eachcol(df))` for a `DataFrame`.

The estimator is the k-nearest-neighbour estimator for mixed discrete-continuous data (Gao et al. 2017; Mesner & Shalizi 2020).
It works for any element type with a `Causifyxion.distance`. On purely discrete data it approximates the plug-in (counting) estimate.
Estimates are noisy and can be slightly negative. Use `independencetest` to decide whether a value is meaningfully above zero.

```julia
x = causify(Normal(0, 1))
y = @causify x + rand(Normal(0, 1))
xs, ys = simulate(2_000, x, y)
mutualinfo(xs, ys) # ≈ -½log(1 - ½) ≈ 0.35
```
"""
mutualinfo(x, y, z = nothing; k::Int = 3) = _conditional_mutualinfo(x, y, z, k)

"""
    shannonentropy(x[, z]; k = 3)

Estimates the Shannon entropy `H(X)` in nats, or the conditional entropy `H(X|Z)` when `z` is given, using `H(X) = I(X;X)`.

This is the entropy of discrete variables. A continuous variable has infinite Shannon entropy, and the estimate grows
without bound (like `log(n/k)`) as the sample grows. Differential entropy is a different quantity and is not estimated here.
`mutualinfo` and `kldiv` do not have this problem: they are comparable across discrete and continuous data.
"""
shannonentropy(x, z = nothing; k::Int = 3) = mutualinfo(x, x, z; k)

"""
    kldiv(p, q; k = 10)

Estimates the Kullback-Leibler divergence `KL(P‖Q)` in nats from a sample `p` of `P` and a sample `q` of `Q`.
Samples are columns, or tuples of columns, as in `mutualinfo`.

For each point of `p`, the estimator compares how many points of `p` and `q` lie within the distance to its `k`-th nearest point in `q`.
This needs no dimension or density, so it works for discrete, continuous and mixed data alike.
The price is that it cannot see beyond the sample of `q`: where `P` has mass in regions `Q` rarely reaches, the divergence is underestimated.
Where `P` puts mass that `Q` does not, the true divergence is infinite but the estimate stays finite.
"""
function kldiv(p, q; k::Int = 10)
    n, m = _length(p), _length(q)
    1 <= k <= m || throw(ArgumentError("k must be between 1 and the size of q ($m), got $k"))
    dp, dq = Vector{Float64}(undef, n), Vector{Float64}(undef, m)
    total = 0.0
    for i in 1:n
        for j in 1:n
            dp[j] = _distance(p, i, p, j)
        end
        for j in 1:m
            dq[j] = _distance(p, i, q, j)
        end
        ρ = partialsort(dq, k)
        total += _digamma(_count_within(dp, ρ, i) + 1) - _digamma(count(<=(ρ), dq))
    end
    return total / n + log(m / n)
end

function _neighbourhoods(z, k)
    n = _length(z)
    distances = Vector{Float64}(undef, n)
    return map(1:n) do i
        for j in 1:n
            distances[j] = _distance(z, i, j)
        end
        ρ = partialsort(distances, k + 1)
        findall(<=(ρ), distances)
    end
end

_permutation(rng::AbstractRNG, ::Nothing, n) = randperm(rng, n)
function _permutation(rng::AbstractRNG, neighbourhoods, n)
    used = falses(n)
    perm = Vector{Int}(undef, n)
    for i in randperm(rng, n)
        free = filter(j -> !used[j], neighbourhoods[i])
        j = rand(rng, isempty(free) ? neighbourhoods[i] : free)
        used[j] = true
        perm[i] = j
    end
    return perm
end

"""
    independencetest(x, y[, z]; k = 3, permutations = 200, rng = Random.default_rng())

Tests whether `x` and `y` are independent (or conditionally independent given `z`) by a permutation test on `mutualinfo`.
Returns `(; estimate, pvalue)`. A small `pvalue` is evidence of dependence.

Without `z`, `x` is shuffled freely. With `z`, `x` is shuffled only among observations with nearby `z`
(a local permutation, Runge 2018), so the relationship between `x` and `z` is kept while any link to `y` is broken.
For a discrete `z` this is a shuffle within each value of `z`.

Arguments are columns, or tuples of columns, as in `mutualinfo`.

```julia
x = causify(Bernoulli(0.5))
y = @causify x ⊻ rand(Bernoulli(0.1))
xs, ys = simulate(500, x, y)
independencetest(xs, ys).pvalue # ≈ 0.005: dependent
```
"""
function independencetest(x, y, z = nothing; k::Int = 3, permutations::Int = 200, rng::AbstractRNG = default_rng())
    n = _length(x)
    estimate = mutualinfo(x, y, z; k)
    neighbourhoods = isnothing(z) ? nothing : _neighbourhoods(z, k)
    exceed = count(1:permutations) do _
        mutualinfo(_permute(x, _permutation(rng, neighbourhoods, n)), y, z; k) >= estimate
    end
    return (; estimate, pvalue = (1 + exceed) / (1 + permutations))
end
