"""
Forces a full fresh resolution of the pre-built `expensive_chain` CausalVariable graph with the `Threaded()` strategy.
"""
function expensive_chain(example)
    refresh!(example.causal)
    resolve!(Threaded(), example.causal)
end
