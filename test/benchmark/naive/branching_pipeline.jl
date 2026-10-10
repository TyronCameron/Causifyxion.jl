_norm(x) = sqrt(sum(abs2, x))

function _moving_average(x)
    n = length(x)
    [sum(x[max(1, i - 1):min(n, i + 1)]) / length(x[max(1, i - 1):min(n, i + 1)]) for i in 1:n]
end

"""
Plain, directly-composed Julia implementation of the same branching/merging pipeline built
with `causify` in `init/branching_pipeline.jl` -- no `CausalVariable` involved.
"""
function branching_pipeline_native(x0a, x0b, s0)
    a1 = x0a ./ (_norm(x0a) + 1e-9)
    a2 = tanh.(a1)
    a3 = cumsum(a2)
    sA = sum(a3)

    b1 = x0b .^ 2
    b2 = _moving_average(b1)
    b3 = clamp.(b2, -5.0, 5.0)
    sB = sum(abs2, b3)

    m1 = a3 .+ b3
    m2 = tanh.(m1)

    c1 = m2 .* s0
    c2 = cumsum(c1)
    sC = sum(c2)

    d1 = reverse(m2)
    d2 = d1 .+ a2
    sD = sum(abs2, d2)

    return sA + sB + sC + sD
end

branching_pipeline(example) = branching_pipeline_native(example.native...)
