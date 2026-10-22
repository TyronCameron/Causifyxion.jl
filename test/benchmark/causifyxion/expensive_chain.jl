"""
Forces a full fresh resolution of the pre-built `expensive_chain` CausalVariable graph with the default `Serial()` strategy.
"""
function expensive_chain(example)
    refresh!(example.causal)
    resolve!(example.causal)
end
