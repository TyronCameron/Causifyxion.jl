"""
Forces a full fresh resolution of the pre-built `expensive_wide` CausalVariable graph with the default `Serial()` strategy.
"""
function expensive_wide(example)
    refresh!(example.causal)
    resolve!(example.causal)
end
