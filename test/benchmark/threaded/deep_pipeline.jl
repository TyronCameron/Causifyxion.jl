"""
Forces a full fresh resolution of the pre-built `deep_pipeline` CausalVariable graph with the `Threaded()` strategy.
"""
function deep_pipeline(example)
    refresh!(example.causal)
    resolve!(Threaded(), example.causal)
end
