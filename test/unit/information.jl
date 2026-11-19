using Random: Xoshiro

@testset "Information" begin
    rng = Xoshiro(1)
    n = 1000

    @testset "mutualinfo: bivariate Gaussian" begin
        for ρ in (0.0, 0.6, 0.9)
            xs = randn(rng, n)
            ys = ρ .* xs .+ sqrt(1 - ρ^2) .* randn(rng, n)
            @test mutualinfo(xs, ys) ≈ -log(1 - ρ^2) / 2 atol = 0.1
        end
    end

    @testset "mutualinfo: discrete matches plug-in" begin
        xs = rand(rng, 1:3, n)
        ys = [rand(rng) < 0.7 ? x : rand(rng, 1:3) for x in xs]
        pxy = [count(i -> xs[i] == a && ys[i] == b, 1:n) / n for a in 1:3, b in 1:3]
        px, py = sum(pxy; dims = 2), sum(pxy; dims = 1)
        plugin = sum(pxy[a, b] * log(pxy[a, b] / (px[a] * py[b])) for a in 1:3, b in 1:3)
        @test mutualinfo(xs, ys) ≈ plugin atol = 0.02
    end

    @testset "mutualinfo: works for any type with equality" begin
        colours = rand(rng, [:red, :green, :blue], n)
        copies = map(c -> rand(rng) < 0.9 ? c : :red, colours)
        @test mutualinfo(colours, copies) > 0.5
        @test abs(mutualinfo(colours, rand(rng, [:red, :green], n))) < 0.02
    end

    @testset "mutualinfo: mixed and multivariate" begin
        bs = rand(rng, Bool, n)
        cs = randn(rng, n) .+ 3 .* bs
        mixture_term(c) = map((0, 3)) do μ
            p, m = pdf(Normal(μ, 1), c), (pdf(Normal(0, 1), c) + pdf(Normal(3, 1), c)) / 2
            p * log(p / m) / 2
        end |> sum
        grid = range(-10, 13; length = 100_001)
        @test mutualinfo(bs, cs) ≈ sum(mixture_term, grid) * step(grid) atol = 0.05
        @test abs(mutualinfo(bs, randn(rng, n))) < 0.05

        xs, ys = randn(rng, n), randn(rng, n)
        zs = xs .+ ys
        @test mutualinfo((xs, ys), zs) > mutualinfo(xs, zs)
        @test mutualinfo((; xs, ys), zs) == mutualinfo((xs, ys), zs)
    end

    @testset "mutualinfo: conditional" begin
        x = causify(Normal(0, 1))
        y = @causify x + rand(Normal(0, 1))
        z = @causify y + rand(Normal(0, 1))
        xs, ys, zs = simulate(n, x, y, z)
        @test mutualinfo(xs, zs) > 0.1
        @test abs(mutualinfo(xs, zs, ys)) < 0.07

        a, b = causify(Normal(0, 1)), causify(Normal(0, 1))
        c = @causify a + b + rand(Normal(0, 0.5))
        as, bs, cs = simulate(n, a, b, c)
        @test abs(mutualinfo(as, bs)) < 0.07
        @test mutualinfo(as, bs, cs) > 0.3
    end

    @testset "shannonentropy" begin
        @test shannonentropy(rand(rng, 1:4, n)) ≈ log(4) atol = 0.02
        xs = rand(rng, 1:4, n)
        @test shannonentropy(xs, xs) ≈ 0 atol = 1e-12
        @test shannonentropy(xs, isodd.(xs)) ≈ log(2) atol = 0.02
    end

    @testset "kldiv" begin
        @test kldiv(randn(rng, n), randn(rng, n)) ≈ 0 atol = 0.05
        @test kldiv(randn(rng, n), randn(rng, n) .+ 1) ≈ 0.5 atol = 0.15
        p, q = [0.5, 0.3, 0.2], [0.2, 0.3, 0.5]
        ps, qs = rand(rng, Categorical(p), n), rand(rng, Categorical(q), n)
        @test kldiv(ps, qs) ≈ sum(p .* log.(p ./ q)) atol = 0.08
        @test_throws ArgumentError kldiv(ps, qs[1:5])
    end

    @testset "independencetest" begin
        x = causify(Bernoulli(0.5))
        y = @causify x ⊻ rand(Bernoulli(0.2))
        z = @causify y ⊻ rand(Bernoulli(0.2))
        w = causify(Bernoulli(0.5))
        xs, ys, zs, ws = simulate(500, x, y, z, w)

        @test independencetest(xs, zs; rng).pvalue < 0.05
        @test independencetest(xs, ws; rng).pvalue > 0.01
        @test independencetest(xs, zs, ys; rng).pvalue > 0.01

        as, bs = randn(rng, 300), randn(rng, 300)
        cs = as .+ bs .+ 0.5 .* randn(rng, 300)
        @test independencetest(as, bs; rng).pvalue > 0.01
        @test independencetest(as, bs, cs; rng).pvalue < 0.05

        result = independencetest(as, bs; permutations = 19, rng)
        @test result.estimate == mutualinfo(as, bs)
        @test result.pvalue in (1:20) ./ 20
    end

    @testset "argument checks" begin
        @test_throws ArgumentError mutualinfo([1, 2, 3], [1, 2, 3])
        @test_throws ArgumentError mutualinfo(randn(10), randn(10); k = 0)
    end
end
