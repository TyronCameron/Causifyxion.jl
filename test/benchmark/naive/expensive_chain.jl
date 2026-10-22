function _work(x, n = 20_000)
    s = x
    for i in 1:n
        s = sin(s) + 1e-3 * i
    end
    return s
end

"""
Plain Julia version of `expensive_chain`: 16 expensive steps applied one after another.
"""
function expensive_chain_native(x0)
    x = x0
    for _ in 1:16
        x = _work(x)
    end
    return x
end

expensive_chain(example) = expensive_chain_native(example.native...)
