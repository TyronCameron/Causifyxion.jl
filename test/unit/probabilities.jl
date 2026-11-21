using Random

struct Colour
    name::Symbol
end

@testset "Probabilities" begin

    @testset "Tally / tally / total" begin
        sample = [3, 1, 2, 2, 3, 3]
        t = tally(sample)

        @test total(t) == length(sample)
        for v in unique(sample)
            @test t(v) == count(==(v), sample)
        end
        @test t(999) == 0
    end

    @testset "Univariate EmpiricalDistribution" begin
        sample = [1, 2, 2, 3, 3, 3]
        d = distribution(sample)

        @test d == distribution(tally(sample))
        @test issetequal(support(d), [1, 2, 3])
        @test sum(probs(d)) ≈ 1.0
        @test total(d) ≈ 1.0

        @test mass(d, 1) ≈ 1/6
        @test mass(d, 2) ≈ 2/6
        @test d(3) ≈ 3/6
        @test mass(d, 99) == 0.0

        @test pdf(d, 2) == mass(d, 2)
        @test logpdf(d, 2) ≈ log(mass(d, 2))

        @test insupport(d, 2)
        @test !insupport(d, 99)

        @test cdf(d, 0) == 0.0
        @test cdf(d, 1) ≈ 1/6
        @test cdf(d, 2) ≈ 3/6
        @test cdf(d, 100) ≈ 1.0

        @test minimum(d) == 1
        @test maximum(d) == 3
    end

    @testset "Any type with equality" begin
        colours = Colour.([:red, :green, :red, :blue])
        d = distribution(colours)
        @test d(Colour(:red)) ≈ 0.5
        @test d(Colour(:pink)) == 0.0
        @test tally(colours)(Colour(:blue)) == 1
        @test map(c -> c.name == :red, d)(true) ≈ 0.5
    end

    @testset "Multivariate EmpiricalDistribution" begin
        xs = [1, 1, 2, 2]
        ys = [:a, :b, :b, :b]
        d = distribution(xs, ys)

        @test d((1, :a)) ≈ 0.25
        @test d((2, :b)) ≈ 0.5
        @test d == distribution((xs, ys))
        @test cdf(distribution(xs, [1, 2, 2, 2]), (1, 2)) ≈ 0.5
        @test_throws DimensionMismatch cdf(distribution(xs, [1, 2, 2, 2]), (1, 2, 3))
    end

    @testset "map / marginal" begin
        d = distribution([1, 1, 2, 2], [:a, :b, :b, :b])

        @test marginal(d, 1) == distribution([1, 1, 2, 2])
        @test marginal(d, 2) == distribution([:a, :b, :b, :b])
        @test marginal(d, (2, 1)) == distribution([:a, :b, :b, :b], [1, 1, 2, 2])
        @test map(s -> isodd(s[1]), d) == distribution([true, true, false, false])

        named = distribution([(x = 1, y = :a), (x = 2, y = :b)])
        @test marginal(named, :y) == distribution([:a, :b])

        t = tally([1, 2, 3, 4])
        @test map(isodd, t)(true) == 2

        @test map(x -> round(x; digits = 1), distribution(rand(1_000))) isa EmpiricalDistribution{Float64}
    end

    @testset "given / |" begin
        d = distribution([1, 1, 2, 2], [:a, :b, :b, :b])

        conditional = d | (s -> s[1] == 2)
        @test conditional((2, :b)) ≈ 1.0
        @test total(conditional) ≈ 1.0
        @test given(d, s -> s[2] == :b) == distribution([1, 2, 2], [:b, :b, :b])

        t = tally([1, 2, 2, 3])
        @test (t | iseven)(2) == 2
        @test total(t | iseven) == 2

        @test_throws ArgumentError d | (s -> false)
    end

    @testset "product / ⊗" begin
        px = distribution([1, 2])
        py = distribution([:a, :a, :b])
        joint = px ⊗ py

        @test joint((1, :a)) ≈ 1/2 * 2/3
        @test total(joint) ≈ 1.0
        @test marginal(joint, 1) ≈ px
        @test marginal(joint, 2) ≈ py

        @test (tally([1, 2]) ⊗ tally([:a, :a]))((1, :a)) == 2

        d = distribution(rand(1:3, 500), rand([:a, :b], 500))
        px = marginal(d, 1)
        rebuilt = product(px, x -> marginal(d | (s -> s[1] == x), 2))
        @test rebuilt ≈ d
    end

    @testset "quantile" begin
        d = distribution([1, 2, 2, 3, 3, 3])

        @test quantile(d, 0.0) == 1
        @test quantile(d, 1.0) == 3
        @test quantile(d, 0.5) == 2

        @test_throws DomainError quantile(d, -0.1)
        @test_throws DomainError quantile(d, 1.1)
    end

    @testset "rand" begin
        d = distribution([1, 2, 2, 3, 3, 3])

        draws = [rand(d) for _ in 1:10_000]
        @test all(v -> insupport(d, v), draws)

        for v in support(d)
            observed = count(==(v), draws) / length(draws)
            @test isapprox(observed, mass(d, v); atol = 0.03)
        end

        rng = Random.default_rng()
        @test rand(rng, d) isa eltype(support(d))
        @test insupport(d, rand(rng, tally([1, 2, 2, 3, 3, 3])))
    end

    @testset "copula" begin
        n = 5_000
        a = rand(n)
        b = a .+ 0.1 .* randn(n)

        cop, marginals = copula((a, b))

        @test length(marginals) == 2
        @test marginals[1] isa EmpiricalDistribution
        @test marginals[2] isa EmpiricalDistribution
        @test cop isa EmpiricalDistribution{Tuple{Float64, Float64}}

        transformed_a = map(s -> cdf(marginals[1], s), a)
        @test isapprox(sum(transformed_a) / n, 0.5; atol = 0.03)
        @test minimum(transformed_a) >= 0.0
        @test maximum(transformed_a) <= 1.0
    end

    @testset "convert to DiscreteNonParametric" begin
        d = distribution([1, 2, 2, 3, 3, 3])
        dnp = convert(DiscreteNonParametric, d)

        @test dnp isa DiscreteNonParametric
        @test issetequal(support(dnp), support(d))
        for v in support(d)
            @test pdf(dnp, v) ≈ pdf(d, v)
        end
    end

    @testset "Integration with simulate" begin
        x = causify(Uniform(0, 1))
        d = distribution(simulate(1000, x))
        @test length(support(d)) > 1
        @test isapprox(sum(probs(d)), 1.0)
        @test 0.0 <= minimum(d)
        @test maximum(d) <= 1.0

        coin = causify(Bernoulli(0.5))
        flipped = @causify !coin
        joint = distribution(1_000, coin, flipped)
        @test joint((true, true)) == 0.0
        @test joint((true, false)) + joint((false, true)) ≈ 1.0
        @test marginal(joint, 1) == map(!, marginal(joint, 2))
    end

end
