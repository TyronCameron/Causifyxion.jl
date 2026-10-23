
@testset "replicate" begin
    @testset "basic: fresh independent copy" begin
        x = causify(Uniform(0,1))
        y = @causify x^2

        z = replicate(y)
        @test z isa CausalVariable
        @test z !== y
        @test isindependent(z, x)

        setvalue!(x, 0.5)
        resolve!(y)
        @test getvalue(y) == 0.25

        @test isunknown(z)
        resolve!(z)
        @test isknown(z)
    end

    @testset "keep: shared ancestor" begin
        x = causify(Uniform(0,1))
        y = @causify x^2

        z = replicate(y, x)

        setvalue!(x, 0.3)
        @test resolve!(z) == 0.09
        @test resolve!(y) == 0.09
    end

    @testset "keep: root identity" begin
        x = causify(Uniform(0,1))
        @test replicate(x, x) === x
    end

    @testset "Tuple `keep` overload parity" begin
        x = causify(Uniform(0,1))
        y = @causify x^2

        z_vararg = replicate(y, x)
        z_tuple = replicate(y, (x,))

        setvalue!(x, 0.7)
        @test resolve!(z_vararg) ≈ 0.49
        @test resolve!(z_tuple) ≈ 0.49
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
        @test length(Set(zs)) == 3
    end

    @testset "with keep: shared ancestor across all replicas" begin
        zs = replicate(3, y, x)

        setvalue!(x, 0.4)
        @test all(z -> resolve!(z) ≈ 0.16, zs)
    end

    @testset "vararg / tuple keep parity" begin
        zs_vararg = replicate(2, y, x)
        zs_tuple = replicate(2, y, (x,))

        setvalue!(x, 0.6)
        @test all(z -> resolve!(z) ≈ 0.36, zs_vararg)
        @test all(z -> resolve!(z) ≈ 0.36, zs_tuple)
    end
end