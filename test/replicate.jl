
@testset "replicate" begin
    @testset "basic: fresh independent copy" begin
        x = causify(Uniform(0,1))
        y = @causify x^2

        z = Causifyxion.replicate(y)
        @test z isa CausalVariable
        @test z !== y
        @test z.dependencies[1] !== x

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

        z = Causifyxion.replicate(y, x)
        @test z.dependencies[1] === x

        setvalue!(x, 0.3)
        @test resolve!(z) == 0.09
        @test resolve!(y) == 0.09
    end

    @testset "keep: root identity" begin
        x = causify(Uniform(0,1))
        @test Causifyxion.replicate(x, x) === x
    end

    @testset "Tuple `keep` overload parity" begin
        x = causify(Uniform(0,1))
        y = @causify x^2

        z_vararg = Causifyxion.replicate(y, x)
        z_tuple = Causifyxion.replicate(y, (x,))

        @test z_vararg.dependencies[1] === x
        @test z_tuple.dependencies[1] === x
    end
end
