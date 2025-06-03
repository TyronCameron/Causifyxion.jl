
@testset "Causify directly" begin 
    x = causify(Normal(0,1))
    y = @causify x^2

    @test y isa CausalVariable

    rand!(y)

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
        @test 10*rand!(x) ≈ rand!(causal_var)
    end 
end 

@testset "Causify assignment" begin
    x = causify(Normal(0,1))
    @causify y = x^2

    @test y isa CausalVariable

    rand!(y)

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
        @test 10*rand!(x) ≈ rand!(causal_var)
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
        @test rand!(e) isa Float64

        # @causify :constants begin
        #     x = causify(Normal(0,1))
        #     y = x^2
        #     d = 15
        #     e = d + y 
        # end

        # @test e isa CausalVariable
        # @test d isa CausalVariable
        # @test rand!(e) isa Float64
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
        @test rand!(e) isa Float64
        @test getvalue(e) ≈ rand!(e)
    end

    # @testset "Contains nested scope" begin
    #     Causifyxion._causify_expr(quote
    #         x = causify(Normal(0,1))
    #         y = x^2
    #         d = 15
    #         e = begin 
    #             g = 100
    #             g*(d + y)
    #         end 
    #     end, Set(); __module__ = @__MODULE__) 

    #     @test e isa CausalVariable
    #     @test !isdefined(@__MODULE__, :f)
    
    # end
end
