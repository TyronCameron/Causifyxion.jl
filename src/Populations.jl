
"""
    Population{T}

An `AbstractCausalVariable` representing `n` i.i.d. draws of a wrapped `CausalVariable{T}`.
Resolving a `Population` draws `n` independent samples, spread across a small pool of
independent replicas (via `replicate`) so sampling can happen in parallel.

A `Population` is a leaf with respect to the dependency DAG: its replicas are an internal
sampling-pool detail, not causal dependencies, so `Taproots.children` returns `()` for it.
"""
mutable struct Population{T} <: AbstractCausalVariable
    replicas::Vector{<:AbstractCausalVariable}
    n::Int
    value::Base.RefValue{Possible{Vector{T}}}
end

Taproots.children(::Population) = ()
Taproots.setchildren!(population::Population, _) = population
Base.copy(p::Population{T}) where T = Population{T}(copy(p.replicas), p.n, Ref(p.value[]))
Base.eltype(::Population{T}) where T = Vector{T}
function Base.show(io::IO, population::Population{T}) where T
    state = @cases population.value[] begin
        Unknown => "Population($(population.n) × Unknown::$(T))"
        Known(x) => "Population($(population.n) × Known::$(T))"
    end
    print(io, state)
end

"""
    population(n::Int, causalvar::AbstractCausalVariable; k::Int = Threads.nthreads())

Build a `Population` of `n` i.i.d. samples of `causalvar`, backed by `k` independent
replicas (via `replicate`) so that resolving the population can sample across them in
parallel.

Example:

```julia
x = causify(Normal(0,1))
pop = population(10_000, x)
samples = resolve!(pop) # a Vector{Float64} of 10,000 independent draws of x
```
"""
function population(n::Int, causalvar::AbstractCausalVariable; k::Int = Threads.nthreads())
    n >= 0 || throw(ArgumentError("n must be non-negative, got $n"))
    k >= 1 || throw(ArgumentError("k must be at least 1, got $k"))
    T = eltype(causalvar)
    replicas = AbstractCausalVariable[replicate(causalvar) for _ in 1:k]
    return Population{T}(replicas, n, Ref{Possible{Vector{T}}}(Unknown))
end

"""
    resolve!(population::Population)

Draws `n` fresh, independent samples of the wrapped causal variable, distributing the work
across the population's replicas via `Threads.@spawn`. If the population is already known,
returns the cached result instead of resampling.
"""
function resolve!(population::Population{T}) where T
    if isknown(population) return getvalue(population) end
    results = Vector{T}(undef, population.n)
    if population.n > 0
        pool = Channel{AbstractCausalVariable}(length(population.replicas))
        foreach(r -> put!(pool, r), population.replicas)
        chunk = max(1, cld(population.n, length(population.replicas)))
        @sync for range in Iterators.partition(1:population.n, chunk)
            Threads.@spawn begin
                replica = take!(pool)
                try
                    for i in range
                        results[i] = simulate!(replica)
                    end
                finally
                    put!(pool, replica)
                end
            end
        end
        close(pool)
    end
    setvalue!(population, results)
    return results
end
