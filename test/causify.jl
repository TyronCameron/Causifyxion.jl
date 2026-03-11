
@testset "Causify" begin 

    # first way defining a causal variable
    x = causify(Normal(0,1))
    @test x isa CausalVariable
    @test eltype(x) <: Real

    # second way, depening on the first
    # defines y to be x^2
    y = causify(x) do x 
        x^2
    end 
    @test y isa CausalVariable
    @test eltype(y) <: Real

    # third way, defines z to be x + y, and type hints at z's eltype. 
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
    
    @test_throws "Perhaps call resolve!" begin 
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

end 

@testset "Reset and rand" begin
    x = causify(Uniform(0,1))
    y = causify(x) do x 
        x^2
    end 
    fresh_sample1 = simulate!(y)
    fresh_sample2 = simulate!(y)

    @test fresh_sample1 != fresh_sample2 # these are 100% fresh samples

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

    tup = simulate!(5, x, y) # first column = 5 fresh samples of x, second column = 5 fresh samples of y; those samples are consistent in each row
    
    @test tup isa Tuple

    xvals, yvals = tup
    @test all(xvals .^ 2 .≈ yvals) # every value in column 1 squared equals every value in column 2

    rigged_tuple = simulate!(5, x, y) do
        setvalue!(x, 0.5)
    end 

    @test all(rigged_tuple[1] .== 0.5)
    @test all(rigged_tuple[2] .== 0.25)

    df = DataFrame(collect(rigged_tuple), [:x, :y])

    @test df isa DataFrame
    @test df.x[1] == 0.5
end
