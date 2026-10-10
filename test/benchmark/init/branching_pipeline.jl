using Random

const BRANCH_N = 32

_norm(x) = sqrt(sum(abs2, x))

function _moving_average(x)
    n = length(x)
    [sum(x[max(1, i - 1):min(n, i + 1)]) / length(x[max(1, i - 1):min(n, i + 1)]) for i in 1:n]
end

"""
Builds the fixed (seeded) inputs for the `branching_pipeline` situation, plus the equivalent
`causify`-built CausalVariable graph: two independent branches that merge, fork again, and
recombine into a final scalar -- exercises shared/multi-dependency nodes rather than a pure
chain.
"""
function branching_pipeline()
    rng = Random.MersenneTwister(7)
    x0a = randn(rng, BRANCH_N)
    x0b = randn(rng, BRANCH_N)
    s0 = randn(rng)

    X0a = causify(() -> x0a)
    X0b = causify(() -> x0b)
    S0 = causify(() -> s0)

    A1 = causify(x -> x ./ (_norm(x) + 1e-9), X0a)
    A2 = causify(x -> tanh.(x), A1)
    A3 = causify(cumsum, A2)
    SA = causify(sum, A3)

    B1 = causify(x -> x .^ 2, X0b)
    B2 = causify(_moving_average, B1)
    B3 = causify(x -> clamp.(x, -5.0, 5.0), B2)
    SB = causify(x -> sum(abs2, x), B3)

    M1 = causify((x, y) -> x .+ y, A3, B3)
    M2 = causify(x -> tanh.(x), M1)

    C1 = causify((x, s) -> x .* s, M2, S0)
    C2 = causify(cumsum, C1)
    SC = causify(sum, C2)

    D1 = causify(reverse, M2)
    D2 = causify((x, y) -> x .+ y, D1, A2)
    SD = causify(x -> sum(abs2, x), D2)

    Result = causify((sa, sb, sc, sd) -> sa + sb + sc + sd, SA, SB, SC, SD)

    return (native = (x0a, x0b, s0), causal = Result)
end
