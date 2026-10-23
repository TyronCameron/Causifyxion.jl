
_tuple_add(a, b) = a + b

@testset "Tuple-accepting causify" begin
    x = causify(Normal(0,1))
    y = causify(Normal(0,1))

    z_tuple = causify(_tuple_add, (x, y))
    z_vararg = causify(_tuple_add, x, y)

    @test z_tuple isa CausalVariable
    @test eltype(z_tuple) == eltype(z_vararg)

    setvalue!(x, 1.0)
    setvalue!(y, 2.0)
    @test resolve!(z_tuple) == resolve!(z_vararg) == 3.0
end

@testset "Tuple-accepting causify with explicit type" begin
    x = causify(Normal(0,1))
    y = causify(Normal(0,1))

    z_tuple = causify(_tuple_add, Float64, (x, y))
    z_vararg = causify(_tuple_add, Float64, x, y)

    @test eltype(z_tuple) === Float64
    @test eltype(z_vararg) === Float64

    setvalue!(x, 1.5)
    setvalue!(y, 2.5)
    @test resolve!(z_tuple) == resolve!(z_vararg) == 4.0
end

@testset "Tuple-accepting resolve! / refresh!" begin
    x = causify(Uniform(0,1))
    y = causify(Uniform(0,1))

    setvalue!(x, 0.25)
    setvalue!(y, 0.75)

    @test resolve!((x, y)) == (0.25, 0.75)
    @test resolve!(x, y) == (0.25, 0.75)

    refresh!((x, y))
    @test isunknown(x) && isunknown(y)
end

@testset "Tuple-accepting isanyknown / isnothingknown" begin
    x = causify(Uniform(0,1))
    y = causify(Uniform(0,1))

    @test isnothingknown((x, y)) == isnothingknown(x, y) == true
    @test isanyknown((x, y)) == isanyknown(x, y) == false

    setvalue!(x, 0.5)

    @test isanyknown((x, y)) == isanyknown(x, y) == true
    @test isnothingknown((x, y)) == isnothingknown(x, y) == false
end

@testset "Tuple-accepting simulate! / simulate" begin
    x = causify(Uniform(0,1))
    y = causify(x) do x
        x^2
    end

    rigged = simulate!((x, y)) do
        setvalue!(x, 0.5)
    end
    @test rigged == (0.5, 0.25)

    tup = simulate!(5, (x, y))
    @test tup isa Tuple
    xvals, yvals = tup
    @test all(xvals .^ 2 .≈ yvals)

    refresh!((x, y))
    result = simulate((x, y))
    @test result isa Tuple
    refresh!((x, y))
end

@testset "Singleton tuple unwrapping (parity with vararg form)" begin
    x = causify(Uniform(0,1))
    setvalue!(x, 0.42)
    @test resolve!((x,)) == 0.42
    @test resolve!((x,)) isa Float64

    y = causify(x) do x
        x^2
    end
    rigged = simulate!((y,)) do
        setvalue!(x, 0.5)
    end
    @test rigged == 0.25
    @test rigged isa Float64
end

@testset "Type inference: tuple-accepting causify + CausalVariable{T,F}" begin
    x = causify(Normal(0,1))
    y = causify(Normal(0,1))

    g(deps) = causify(_tuple_add, deps)

    z = @inferred g((x, y))
    @test z isa CausalVariable
    @test eltype(z) === Float64

    w = @inferred causify(_tuple_add, x, y)
    @test w isa CausalVariable
    @test eltype(w) === Float64
end
