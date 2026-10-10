"""
Forces a full fresh resolution of the pre-built `branching_pipeline` CausalVariable graph
(not a cache hit): `refresh!` invalidates every node, then `resolve!` walks and recomputes
the DAG.
"""
function branching_pipeline(example)
    refresh!(example.causal)
    resolve!(example.causal)
end
