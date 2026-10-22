"""
Forces a full fresh resolution of the pre-built `branching_pipeline` CausalVariable graph with the `Threaded()` strategy.
"""
function branching_pipeline(example)
    refresh!(example.causal)
    resolve!(Threaded(), example.causal)
end
