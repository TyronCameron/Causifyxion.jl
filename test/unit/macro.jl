
@testset "Causify directly" begin 
    x = causify(Normal(0,1))
    y = @causify x^2

    @test y isa CausalVariable

    resolve!(y)

    @test getvalue(y) == getvalue(x)^2

    @testset "nested scope" begin 
        function foo()
            s = x
            for i in 2:10
                s = @causify s + x
            end
            return s 
        end

        causal_var = foo()
        @test 10*resolve!(x) ≈ resolve!(causal_var)
    end 

    @testset "Nested otherwise scoped variables" begin
        h = 25
        a = causify(Normal(0,1))
        b = @causify a^2 + abs(rand(Normal(0,1))) + h
        @test b isa CausalVariable
        @test resolve!(b) > resolve!(a)^2
    end

end 

@testset "Causify assignment" begin
    x = causify(Normal(0,1))
    @causify y = x^2

    @test y isa CausalVariable

    resolve!(y)

    @test getvalue(y) == getvalue(x)^2

    @testset "nested scope" begin 
        function foo()
            s = x
            for i in 2:10
                @causify s = s + x
            end
            return s 
        end

        causal_var = foo()
        @test 10*resolve!(x) ≈ resolve!(causal_var)
        @test !isdefined(@__MODULE__, :s)
    end 

end

@testset "Causify whole scope" begin
    @testset "Basic" begin
        
        @causify begin
            x = causify(Normal(0,1))
            y = x^2
            d = 15
            e = d + y 
        end

        @test e isa CausalVariable
        @test !(d isa CausalVariable)
        @test resolve!(e) isa Float64

        x = causify(Normal(0,1))
        @causify :constants begin
            y = x^2
            d = 15
            e = d + y 
        end

        @test e isa CausalVariable
        @test d isa CausalVariable
        @test resolve!(e) isa Float64
    end


    @testset "Within nested scope" begin
        foo() = begin
            @causify begin
                x = causify(Normal(0,1))
                y = x^2
                d = 15
                e = d + y 
            end

            return e 
        end

        e = foo()

        @test e isa CausalVariable 
        @test resolve!(e) isa Float64
        @test getvalue(e) ≈ resolve!(e)
    end

    @testset "Contains nested scope" begin
        @causify begin 
            x = causify(Normal(0,1))
            y = x^2
            d = 15
            e = begin 
                g = 100
                g*(d + y)
            end 
        end

        @test e isa CausalVariable
        @test !isdefined(@__MODULE__, :f)
    end
end

@testset "Type inference" begin
    x = causify(Normal(0,1))
    g(x) = @causify x + 1.0
    @test (@inferred g(x)) isa CausalVariable
    @test eltype(g(x)) === Float64
    h(a, b) = @causify a + b # no-causals path collapses to plain evaluation
    @test @inferred(h(1.0, 2)) === 3.0
end

@testset "Dependency detection for AbstractCausalVariable subtypes" begin
    # Population is an AbstractCausalVariable but not a CausalVariable -- @causify must
    # still recognize it as a real dependency rather than an inert captured constant.
    x = causify(() -> 1.0)
    pop = population(5, x)
    resolve!(pop) # Population must already be known before being used as a dependency here

    z = @causify sum(pop)

    @test z isa CausalVariable
    @test dependson(z, pop) # captured as a real dependency, not evaluated eagerly as a constant
    @test resolve!(z) == 5.0    # 5 draws of a constant-1.0 resolver, summed
end
