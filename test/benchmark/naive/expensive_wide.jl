function _work(x, n = 20_000)
    s = x
    for i in 1:n
        s = sin(s) + 1e-3 * i
    end
    return s
end

"""
Plain Julia version of `expensive_wide`: each of 16 branches applies 3 expensive steps, then everything is summed.
"""
function expensive_wide_native(x0)
    total = 0.0
    for i in 1:16
        x = _work(x0 + i)
        for _ in 2:3
            x = _work(x)
        end
        total += x
    end
    return total
end

expensive_wide(example) = expensive_wide_native(example.native...)
