"""
Forces a full fresh resolution of the pre-built `expensive_wide` CausalVariable graph with the `Threaded()` strategy.
"""
function expensive_wide(example)
    refresh!(example.causal)
    resolve!(Threaded(), example.causal)
end
