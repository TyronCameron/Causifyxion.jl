_norm(x) = sqrt(sum(abs2, x))

function _moving_average(x)
    n = length(x)
    [sum(x[max(1, i - 1):min(n, i + 1)]) / length(x[max(1, i - 1):min(n, i + 1)]) for i in 1:n]
end

"""
Plain, directly-composed Julia implementation of the same 18-stage pipeline built with
`causify` in `init/deep_pipeline.jl` -- no `CausalVariable` involved, just a user writing
and calling their own functions.
"""
function deep_pipeline_native(x0, M)
    x1 = x0 ./ (_norm(x0) + 1e-9)
    x2 = tanh.(x1 .* 2.0)
    x3 = x2 .+ 0.1
    x4 = _moving_average(x3)
    x5 = x4 .^ 2
    s6 = sum(x5)
    s7 = log1p(abs(s6))
    x8 = x4 .* s7
    x9 = cumsum(x8)
    x10 = x9 .+ reverse(x8)
    x11 = clamp.(x10, -10.0, 10.0)
    s12 = sum(abs2, x11)
    s13 = sqrt(abs(s12) + 1e-9)
    x14 = x11 ./ (s13 + 1e-9)
    x15 = M * x14
    x16 = x15 .* exp.(-0.01 .* (1:length(x15)))
    s17 = sum(abs2, x16)
    return s17 + s13
end

deep_pipeline(example) = deep_pipeline_native(example.native...)
