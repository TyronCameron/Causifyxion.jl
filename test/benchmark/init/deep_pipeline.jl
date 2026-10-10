using Random

const DEEP_PIPELINE_N = 32

_norm(x) = sqrt(sum(abs2, x))

function _moving_average(x)
    n = length(x)
    [sum(x[max(1, i - 1):min(n, i + 1)]) / length(x[max(1, i - 1):min(n, i + 1)]) for i in 1:n]
end

"""
Builds the fixed (seeded) inputs for the `deep_pipeline` situation, plus the equivalent
`causify`-built CausalVariable graph (built once here, like Taproots.jl builds its example
trees in `init/` rather than inside the benchmarked function).
"""
function deep_pipeline()
    rng = Random.MersenneTwister(42)
    x0 = randn(rng, DEEP_PIPELINE_N)
    M = randn(rng, DEEP_PIPELINE_N, DEEP_PIPELINE_N) .* 0.05

    X0 = causify(() -> x0)
    X1 = causify(x -> x ./ (_norm(x) + 1e-9), X0)
    X2 = causify(x -> tanh.(x .* 2.0), X1)
    X3 = causify(x -> x .+ 0.1, X2)
    X4 = causify(_moving_average, X3)
    X5 = causify(x -> x .^ 2, X4)
    S6 = causify(sum, X5)
    S7 = causify(s -> log1p(abs(s)), S6)
    X8 = causify((x, s) -> x .* s, X4, S7)
    X9 = causify(cumsum, X8)
    X10 = causify((x, y) -> x .+ reverse(y), X9, X8)
    X11 = causify(x -> clamp.(x, -10.0, 10.0), X10)
    S12 = causify(x -> sum(abs2, x), X11)
    S13 = causify(s -> sqrt(abs(s) + 1e-9), S12)
    X14 = causify((x, s) -> x ./ (s + 1e-9), X11, S13)
    X15 = causify(x -> M * x, X14)
    X16 = causify(x -> x .* exp.(-0.01 .* (1:length(x))), X15)
    S17 = causify(x -> sum(abs2, x), X16)
    Result = causify((s17, s13) -> s17 + s13, S17, S13)

    return (native = (x0, M), causal = Result)
end
