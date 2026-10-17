
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
