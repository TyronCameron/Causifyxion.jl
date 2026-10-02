
# Thought 1
    # Create variations of CausalVariables ... which can do i.i.d. variables and sample from them fast 

# Thought 2
    # Allow parallel sampling ... 

# Thought 3
    # Allow probability distribution gathering ... through sampling only 
    # Subtask: create A given B 

# ---

x = @causify rand(Normal(0,1))
y = @causify x^2 + rand(Normal(0,0.1))

"""
    tally(samples)

Return a dictionary which is the frequency table of the samples. 
"""
tally!(samples::AbstractVector{T}; init = Dict{T, Int}(), by = identity) where T = reduce(samples, init = init) do dict, sample 
    s = by(sample)
    dict[s] = get(dict, s, 0) + 1
    dict
end 

"""
    tally(sparents_to_samples::Dict{S, <:AbstractVector{T}})

Return a nested dictionary, which is the frequency table of the parentsample-sample combinations. 
"""
tally!(parents_to_samples::Dict{T, <:AbstractVector{S}}; by = identity) where {S, T} = reduce(
    pairs(parents_to_samples), 
    init = Dict{T, Dict{S, Int}}()
) do dict, (parentkey, samples) 
    dict[parentkey] = tally!(samples; init = get(dict, parentkey, Dict{S, Int}()), by = by)
    dict
end 

# ---

# Alternatively we take the distribution route 

function distribution(
    intervention!, 
    causalvars::CausalVariable...;
    given = CausalVariable(() -> true), 
    by = identity,
    loss = () -> 0,
    tolerance = () -> 0,
    n = 1_000, 
    maxn = 10^7,
    prior = p
)
    
end
distribution(xs::CausalVariable...; kw...) = distribution(() -> nothing, xs...; kw...)

# Now this can factorise over the graph -- so we only need the distribution for each value inside there 

# I would want a way to use Bayes theorem without relying on rejection sampling as above as well. 

# I think it might be okay to make Distribution use Dirichlet (Jeffrey's) prior plus multinomial. Multinomial covers everything else and Jeffreys prior is no information known at all. 
# It's gonna disappear in the lim anyway. 
# And those are conjugate which makes it computationally better 
# Still a little scared because of dimensionality, but I think the graph might just solve a bunch of that anyway. 
# Also scared about continuous values. Might need to allow you to pass a likelihood function as well. Not sure yet. 