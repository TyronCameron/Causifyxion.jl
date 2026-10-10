
@testset "isexclusive / isexhaustive / isbasis" begin
    @testset "isexclusive" begin
        a = causify(Normal(0,1))
        z = causify(Normal(0,1))  # independent of a, no shared ancestry
        b = @causify a^2          # depends on a
        c = @causify b + 1        # depends on b (and transitively a)
        r = @causify a + z        # depends on both a and z directly

        @test isexclusive(r, (a,))      # single covariate, trivially exclusive
        @test isexclusive(r, (a, z))    # a and z share no ancestry
        @test !isexclusive(c, (a, b))   # b's ancestry includes a -> a mediates b's effect on c
        @test !isexclusive(c, (b, z))   # z isn't even reachable from c -> never "found" -> not exclusive-complete
        @test !isexclusive(r, (a, a))   # duplicate -> length mismatch guard

        @test isexclusive(r, a, z) == isexclusive(r, (a, z))   # vararg/tuple parity
        @test isexclusive(c, a, b) == isexclusive(c, (a, b))
    end

    @testset "isexhaustive" begin
        a = causify(Normal(0,1))
        b = @causify a^2
        c = @causify b + 1

        @test isexhaustive(c, (b,))   # nearest covariate blocks the only path
        @test isexhaustive(c, (a,))   # blocking further up the chain also suffices
        @test !isexhaustive(c, ())    # nothing blocks -> reaches the uncovered root `a`
        @test isexhaustive(c, (c,))   # response is its own covariate -> short-circuit true

        @test isexhaustive(c, b) == isexhaustive(c, (b,))
        @test isexhaustive(c) == isexhaustive(c, ())
    end

    @testset "isbasis is a genuine AND, not a delegate" begin
        a = causify(Normal(0,1))
        b = @causify a^2

        # necessary (trivially, empty set) but not sufficient
        @test isexclusive(b, ())
        @test !isexhaustive(b, ())
        @test !isbasis(b, ())

        # sufficient (response is its own covariate) but not necessary (overlapping ancestry)
        @test isexhaustive(b, (a, b))
        @test !isexclusive(b, (a, b))
        @test !isbasis(b, (a, b))

        # both hold
        @test isexclusive(b, (a,))
        @test isexhaustive(b, (a,))
        @test isbasis(b, (a,))
    end
end

@testset "replicate(n, causalvar, keep...)" begin
    x = causify(Uniform(0,1))
    y = @causify x^2

    @testset "no keep: n independent replicas" begin
        zs = replicate(3, y)
        @test zs isa Vector
        @test length(zs) == 3
        @test all(z -> z isa CausalVariable, zs)
        @test all(z -> z !== y, zs)
        @test length(Set(zs)) == 3  # pairwise distinct objects
    end

    @testset "with keep: shared ancestor across all replicas" begin
        zs = replicate(3, y, x)
        @test all(z -> z.dependencies[1] === x, zs)

        setvalue!(x, 0.4)
        @test all(z -> resolve!(z) ≈ 0.16, zs)
    end

    @testset "vararg / tuple keep parity" begin
        zs_vararg = replicate(2, y, x)
        zs_tuple = replicate(2, y, (x,))
        @test all(z -> z.dependencies[1] === x, zs_vararg)
        @test all(z -> z.dependencies[1] === x, zs_tuple)
    end
end

@testset "Heterogeneous-type dispatch regression (guards NTuple{N,<:X} homogeneity bug)" begin
    x = causify(Normal(0,1))          # CausalVariable{Float64, F1}
    y = @causify x^2                  # CausalVariable{Float64, F2}, F2 != F1
    z = causify(Bernoulli(0.5))       # CausalVariable{Bool, F3}, a third, differently-typed variable

    @test typeof(x) != typeof(y)
    @test typeof(x) != typeof(z)

    deps = (x, y, z)

    @test causify((a,b,c) -> (a,b,c), deps) isa CausalVariable

    setvalue!(x, 0.5); setvalue!(y, 0.25); setvalue!(z, true)
    @test resolve!(deps) == (0.5, 0.25, true)

    refresh!(deps)
    @test isnothingknown(deps)

    @test simulate!(deps) isa Tuple

    refresh!(deps)
    @test isanyknown(deps) == false

    @test isexclusive(x, deps) isa Bool
    @test isexhaustive(x, deps) isa Bool
    @test isbasis(x, deps) isa Bool
end
