const WIDE_BRANCHES = 16
const WIDE_DEPTH = 3
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
Builds the `expensive_wide` situation: one shared input fanning out into `WIDE_BRANCHES` independent chains of
`WIDE_DEPTH` expensive nodes each, merged into a single result. Lots of independent work, so threading should win.
"""
function expensive_wide()
    x0 = 0.5
    X0 = causify(() -> x0)
    tops = map(1:WIDE_BRANCHES) do i
        node = causify(x -> _work(x + i), X0)
        for _ in 2:WIDE_DEPTH
            node = causify(_work, node)
        end
        node
    end
    Result = causify((xs...) -> sum(xs), Float64, tops...)
    return (native = (x0,), causal = Result)
end
