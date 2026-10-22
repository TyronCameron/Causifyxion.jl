const CHAIN_LENGTH = 16
const WORK_ITERATIONS = 20_000 # roughly 100-200 µs of scalar work per call

# Deterministic, allocation-free busy work standing in for an expensive resolver.
function _work(x, n = WORK_ITERATIONS)
    s = x
    for i in 1:n
        s = sin(s) + 1e-3 * i
    end
    return s
end

"""
Builds the `expensive_chain` situation: `CHAIN_LENGTH` expensive nodes in a single chain. Nothing can run in
parallel, so this isolates the threaded scheduler's overhead when the resolvers are expensive.
"""
function expensive_chain()
    x0 = 0.5
    node = causify(() -> x0)
    for _ in 1:CHAIN_LENGTH
        node = causify(_work, node)
    end
    return (native = (x0,), causal = node)
end
