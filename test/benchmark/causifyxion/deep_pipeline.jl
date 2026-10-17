"""
Forces a full fresh resolution of the pre-built `deep_pipeline` CausalVariable graph (not a
cache hit): `refresh!` invalidates every node, then `resolve!` walks and recomputes the DAG.
"""
function deep_pipeline(example)
    refresh!(example.causal)
    resolve!(example.causal)
end
