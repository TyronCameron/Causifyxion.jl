using Random: Xoshiro

struct Shape
    sides::Int
end

@testset "Information" begin
    rng = Xoshiro(1)

    @testset "entropy / crossentropy / kldivergence" begin
        uniform = distribution([1, 2, 3, 4])
        @test entropy(uniform) ≈ log(4)
        @test entropy(tally([1, 2, 3, 4])) ≈ log(4)
        @test entropy(distribution([:a, :a])) == 0.0

        p = distribution([1, 1, 2])
        q = distribution([1, 2, 2, 2])
        @test crossentropy(p, q) ≈ -(2/3 * log(1/4) + 1/3 * log(3/4))
        @test kldivergence(p, q) ≈ crossentropy(p, q) - entropy(p)
        @test kldivergence(p, p) == 0.0
        @test kldivergence(p, tally([1, 2, 2, 2])) ≈ kldivergence(p, q)

        @test kldivergence(distribution([1, 2]), distribution([1, 1])) == Inf
        @test kldivergence(distribution([1, 1]), distribution([1, 2])) ≈ log(2)
    end

    @testset "mutualinfo: exact values" begin
        xs, ys = [1, 1, 2, 2], [:a, :b, :b, :b]
        expected = 1/4 * log(2) + 1/4 * log(2/3) + 1/2 * log(4/3)
        @test mutualinfo(xs, ys) ≈ expected
        @test mutualinfo(distribution(xs, ys)) ≈ expected
        @test mutualinfo(tally(collect(zip(xs, ys)))) ≈ expected

        @test mutualinfo(xs, xs) ≈ entropy(distribution(xs))
        @test mutualinfo(distribution([1, 2, 3]) ⊗ distribution([:a, :b])) ≈ 0 atol = 1e-12
    end

    @testset "mutualinfo: conditional, exact" begin
        pz = distribution([true, false, false])
        joint = product(pz, z -> z ? distribution([1, 2]) ⊗ distribution([:a]) : distribution([1, 1, 2]) ⊗ distribution([:a, :b]))
        xyz = map(((z, (x, y)),) -> (x, y, z), joint)
        @test mutualinfo(xyz) ≈ 0 atol = 1e-12
        @test mutualinfo(marginal(xyz, (1, 3))) > 0

        xs, zs = [1, 2, 1, 2], [1, 1, 2, 2]
        @test mutualinfo(xs, xs, zs) ≈ log(2)
    end

    @testset "mutualinfo: any type" begin
        shapes = Shape.([3, 4, 4, 5])
        colours = [:red, :blue, :blue, :green]
        @test mutualinfo(shapes, colours) ≈ entropy(distribution(shapes))
        @test mutualinfo(shapes, fill(:red, 4)) == 0.0
    end

    @testset "mutualinfo: chain and collider" begin
        n = 5_000
        x = causify(Bernoulli(0.5))
        y = @causify x ⊻ rand(Bernoulli(0.2))
        z = @causify y ⊻ rand(Bernoulli(0.2))
        xs, ys, zs = simulate(n, x, y, z)
        @test mutualinfo(xs, zs) > 0.05
        @test mutualinfo(xs, zs, ys) < 0.005

        a, b = causify(Bernoulli(0.5)), causify(Bernoulli(0.5))
        c = @causify a ⊻ b
        as, bs, cs = simulate(n, a, b, c)
        @test mutualinfo(as, bs) < 0.005
        @test mutualinfo(as, bs, cs) ≈ log(2) atol = 0.01
    end

    @testset "independencetest" begin
        x = causify(Bernoulli(0.5))
        y = @causify x ⊻ rand(Bernoulli(0.2))
        z = @causify y ⊻ rand(Bernoulli(0.2))
        w = causify(DiscreteUniform(1, 4))
        xs, ys, zs, ws = simulate(500, x, y, z, w)

        @test independencetest(xs, zs; rng).pvalue < 0.05
        @test independencetest(xs, ws; rng).pvalue > 0.01
        @test independencetest(xs, zs, ys; rng).pvalue > 0.01
        @test independencetest(xs, ys, ws; rng).pvalue < 0.05

        result = independencetest(xs, ws; permutations = 19, rng)
        @test result.estimate == mutualinfo(xs, ws)
        @test result.pvalue in (1:20) ./ 20
    end
end
