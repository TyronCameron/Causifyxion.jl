
@testset "isexclusive / isexhaustive / isbasis" begin
    @testset "isexclusive" begin
        a = causify(Normal(0,1))
        z = causify(Normal(0,1))
        b = @causify a^2
        c = @causify b + 1
        r = @causify a + z

        @test isexclusive(r, (a,))
        @test isexclusive(r, (a, z))
        @test !isexclusive(c, (a, b))
        @test !isexclusive(c, (b, z))
        @test !isexclusive(r, (a, a))

        @test isexclusive(r, a, z) == isexclusive(r, (a, z))
        @test isexclusive(c, a, b) == isexclusive(c, (a, b))
    end

    @testset "isexhaustive" begin
        a = causify(Normal(0,1))
        b = @causify a^2
        c = @causify b + 1

        @test isexhaustive(c, (b,))
        @test isexhaustive(c, (a,))
        @test !isexhaustive(c, ())
        @test isexhaustive(c, (c,))

        @test isexhaustive(c, b) == isexhaustive(c, (b,))
        @test isexhaustive(c) == isexhaustive(c, ())
    end

    @testset "isbasis is a genuine AND, not a delegate" begin
        a = causify(Normal(0,1))
        b = @causify a^2

        @test isexclusive(b, ())
        @test !isexhaustive(b, ())
        @test !isbasis(b, ())

        @test isexhaustive(b, (a, b))
        @test !isexclusive(b, (a, b))
        @test !isbasis(b, (a, b))

        @test isexclusive(b, (a,))
        @test isexhaustive(b, (a,))
        @test isbasis(b, (a,))
    end
end
