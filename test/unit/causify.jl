
@testset "Causify" begin 

    x = causify(Normal(0,1))
    @test x isa CausalVariable
    @test eltype(x) <: Real

    y = causify(x) do x 
        x^2
    end 
    @test y isa CausalVariable
    @test eltype(y) <: Real

    z = causify(Float64, x, y) do x, y 
        x + y 
    end 
    @test z isa CausalVariable
    @test eltype(z) <: Float64 

    @test_throws MethodError begin
        z = causify(Float64, causify(Normal(0,1))) do x, y 
            x + y 
        end 
        resolve!(z)
    end

end 

@testset begin 
    x = causify(Normal(0,1))
    y = causify(x) do x 
        x^2
    end 
    
    @test_throws ValueUnknownError begin
        getvalue(x)
    end

    @test_throws MethodError begin 
        setvalue!(x, "A string instead of a float64")
    end 

    setvalue!(x, 100.0)
    @test getvalue(x) == 100.0

    @test isknown(x)
    @test isunknown(y)

    resolve!(y)
    refresh!(x)

    @test isknown(y)
    @test isunknown(x)

    @test getvalue(y) == 10000
    @test dependson(y, x)
    @test !dependson(x, y)

end

@testset "Reset and rand" begin
    x = causify(Uniform(0,1))
    y = causify(x) do x 
        x^2
    end 
    fresh_sample1 = simulate!(y)
    fresh_sample2 = simulate!(y)

    @test fresh_sample1 != fresh_sample2

    rigged_value = simulate!(y) do
        setvalue!(x, 0.5)
    end 

    @test rigged_value == 0.25 
end

@testset "simulate! n" begin
    x = causify(Uniform(0,1))
    y = causify(x) do x 
        x^2
    end 

    tup = simulate!(5, x, y)
    
    @test tup isa Tuple

    xvals, yvals = tup
    @test all(xvals .^ 2 .≈ yvals)

    rigged_tuple = simulate!(5, x, y) do
        setvalue!(x, 0.5)
    end 

    @test all(rigged_tuple[1] .== 0.5)
    @test all(rigged_tuple[2] .== 0.25)

    df = DataFrame(collect(rigged_tuple), [:x, :y])

    @test df isa DataFrame
    @test df.x[1] == 0.5
end

@testset "ergonomics" begin
    x = causify(Uniform(0,1))
    y = causify(x) do x
        x^2
    end

    setvalue!(x, 1)
    @test resolve!(y) == 1
end

@testset "Independence" begin
    x1 = causify(Normal(0,1))
    x2 = causify(Normal(0,1))
    @test isindependent(x1, x2)

    z = causify(x1) do x1
        x1^2
    end
    @test !isindependent(x1, z)
    @test !isindependent(z, x1)
    @test Causifyxion.degree(x1) == 0
    @test Causifyxion.degree(z) == 1

    s = causify(Normal(0,1))
    x = causify(x1, s) do x1, s
        x1 + s
    end
    a = causify(s) do s
        s + 1
    end
    @test !isindependent(x, a)
    @test isindependent(x1, a)
end

@testset "Conditional probability (given / |)" begin
    A = causify(Bernoulli(0.7))
    B = causify(A) do a
        rand(Bernoulli(a ? 0.9 : 0.1))
    end

    conditioned = B | A

    setvalue!(A, true)
    setvalue!(B, false)
    @test resolve!(given(B, A)) === false
    setvalue!(A, false)
    @test resolve!(given(B, A)) === missing
    refresh!(A); refresh!(B)

    n = 20_000
    samples = simulate!(n, conditioned)
    @test eltype(samples) == Union{Bool,Missing}

    kept = collect(skipmissing(samples))
    p_a = count(!ismissing, samples) / n
    p_b_given_a = count(kept) / length(kept)

    @test isapprox(p_a, 0.7; atol = 0.03)
    @test isapprox(p_b_given_a, 0.9; atol = 0.05)
end

