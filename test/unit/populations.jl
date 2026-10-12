
@testset "Population" begin
    @testset "construction" begin
        x = causify(Normal(0,1))

        pop = population(100, x)
        @test pop isa Population{Float64}
        @test length(resolve!(pop)) == 100

        pop_k = population(100, x; k = 3)
        @test length(resolve!(pop_k)) == 100 # k is just an internal parallelism knob, output size is unaffected

        @test_throws ArgumentError population(-1, x)
        @test_throws ArgumentError population(10, x; k = 0)
    end

    @testset "leaf w.r.t. the dependency DAG" begin
        x = causify(Normal(0,1))
        pop = population(10, x)

        @test Causifyxion.degree(pop) == 0
    end

    @testset "initially unknown" begin
        x = causify(Normal(0,1))
        pop = population(10, x)

        @test isunknown(pop)
        @test !isknown(pop)
    end

    @testset "resolve! with a deterministic resolver" begin
        x = causify(() -> 1.0)
        pop = population(50, x; k = 4)

        samples = resolve!(pop)
        @test samples isa Vector{Float64}
        @test length(samples) == 50
        @test all(==(1.0), samples)
        @test isknown(pop)

        # Cached: a second resolve! returns the identical object, no resampling
        samples2 = resolve!(pop)
        @test samples2 === samples
    end

    @testset "n == 0 edge case" begin
        x = causify(() -> 1.0)
        pop = population(0, x)

        samples = resolve!(pop)
        @test samples == Float64[]
        @test isknown(pop)
    end

    @testset "generic refresh!/simulate! reuse (no Population-specific override needed)" begin
        x = causify(() -> 1.0)
        pop = population(20, x; k = 2)

        resolve!(pop)
        @test isknown(pop)

        refresh!(pop)
        @test isunknown(pop)

        fresh = simulate!(pop)
        @test fresh isa Vector{Float64}
        @test length(fresh) == 20
        @test isknown(pop)
    end

    @testset "statistical sanity check: independent Bernoulli draws" begin
        x = causify(Bernoulli(0.5))
        pop = population(5000, x; k = Threads.nthreads())

        samples = resolve!(pop)
        @test length(samples) == 5000
        @test all(s -> s isa Bool, samples)
        @test isapprox(sum(samples) / length(samples), 0.5; atol = 0.05)

        # Not every replica just repeats one fixed value across all its draws
        @test length(Set(samples)) == 2
    end
end
