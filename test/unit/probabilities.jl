
using Random

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
        d_from_sample = distribution(sample)
        d_from_tally = distribution(tally(sample))

        @test support(d_from_sample) == support(d_from_tally) == [1, 2, 3]
        @test probs(d_from_sample) ≈ [1/6, 2/6, 3/6]
        @test sum(probs(d_from_sample)) ≈ 1.0

        @test mass(d_from_sample, 1) ≈ 1/6
        @test mass(d_from_sample, 2) ≈ 2/6
        @test mass(d_from_sample, 3) ≈ 3/6
        @test mass(d_from_sample, 99) == 0.0

        @test pdf(d_from_sample, 2) == mass(d_from_sample, 2)
        @test logpdf(d_from_sample, 2) ≈ log(mass(d_from_sample, 2))

        @test insupport(d_from_sample, 2)
        @test !insupport(d_from_sample, 99)

        @test cdf(d_from_sample, 0) == 0.0
        @test cdf(d_from_sample, 1) ≈ 1/6
        @test cdf(d_from_sample, 2) ≈ 3/6
        @test cdf(d_from_sample, 3) ≈ 1.0
        @test cdf(d_from_sample, 100) ≈ 1.0

        @test minimum(d_from_sample) == 1
        @test maximum(d_from_sample) == 3

        @test d_from_sample(2) == cdf(d_from_sample, 2)
    end

    @testset "Multivariate distribution" begin
        xs = [1, 1, 2, 2]
        ys = [10, 20, 10, 20]
        d_cols = distribution(xs, ys)
        d_tuple = distribution((xs, ys))

        @test cdf(d_cols, (2, 20)) == 1.0
        @test cdf(d_cols, (1, 10)) ≈ 1/4
        @test cdf(d_tuple, (2, 20)) == cdf(d_cols, (2, 20))

        @test_throws DimensionMismatch cdf(d_cols, (1,))
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
    end

    @testset "tally(::EmpiricalDistribution) round-trip" begin
        sample = rand(1:7, 10_000)
        t = tally(sample)
        d = distribution(t)
        t2 = tally(d)

        for v in unique(sample)
            @test t2(v) == t(v)
        end
        @test total(t2) == total(t)
    end

    @testset "copula" begin
        n = 5_000
        a = rand(n)
        b = a .+ 0.1 .* randn(n)

        cop, marginals = copula((a, b))

        @test length(marginals) == 2
        @test marginals[1] isa EmpiricalDistribution
        @test marginals[2] isa EmpiricalDistribution

        transformed_a = marginals[1].(a)
        @test isapprox(sum(transformed_a) / n, 0.5; atol = 0.03)
        @test minimum(transformed_a) >= 0.0
        @test maximum(transformed_a) <= 1.0
    end

    @testset "convert to DiscreteNonParametric" begin
        d = distribution([1, 2, 2, 3, 3, 3])
        dnp = convert(DiscreteNonParametric, d)

        @test dnp isa DiscreteNonParametric
        @test support(dnp) == support(d)
        for v in support(d)
            @test pdf(dnp, v) ≈ pdf(d, v)
        end
    end

    @testset "Integration with simulate" begin
        x = causify(Uniform(0, 1))
        samples = simulate(1000, x)

        d = distribution(samples)
        @test length(support(d)) > 1
        @test isapprox(sum(probs(d)), 1.0)
        @test 0.0 <= minimum(d)
        @test maximum(d) <= 1.0
    end

end
