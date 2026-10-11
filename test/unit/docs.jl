
using Dates

@testset "Docs" begin

    @testset "Intro" begin
        x = causify() do # `x` is "Yes" in the first half a minute, and "No" otherwise
            Dates.second(now()) <= 30 ? "Yes" : "No"
        end

        @test x isa CausalVariable
        @test eltype(x) <: String

        @test_throws "Perhaps call resolve!" getvalue(x)

        underlying_value = resolve!(x) # returns either "Yes" or "No"
        @test getvalue(x) === underlying_value

        refresh!(x)
        new_underlying_value = resolve!(x) # returns a new value
        @test new_underlying_value isa String

        x = causify(Normal(10,3))
        y = causify(Uniform(0,1))

        z = causify(x, y) do x, y
            length(x) * 500 + y
        end

        @test eltype(z) <: Float64 # type inferred
        @test resolve!(z) == length(getvalue(x)) * 500 + getvalue(y)

        refresh!(z)
        xvals, yvals, zvals = simulate(10, x, y, z) # can easily destructure
        @test length(xvals) == length(yvals) == length(zvals) == 10

        df = DataFrame(collect(simulate(10, x, y, z)), [:x, :y, :z])
        @test df isa DataFrame
        @test size(df, 1) == 10

        resolve!(z) # ensure all values are set

        # invalidate all vars between `z` and `x`
        # (taking every possible route to get there).
        invalidate!(z, x)

        @test isunknown(x)
        @test isunknown(z)
        @test isknown(y)
    end

    @testset "Getting and setting single values" begin
        causalvar = causify() do
            rand()
        end

        setvalue!(causalvar, 10.0) # can set the value
        @test getvalue(causalvar) == 10.0 # can get the value

        @test isknown(causalvar) == !isunknown(causalvar) == true

        setunknown!(causalvar)
        @test isunknown(causalvar)

        @test_throws "Perhaps call resolve!" getvalue(causalvar)
    end

    @testset "Creating Causal Variables" begin
        x = causify(Uniform(0,1))
        @test x isa CausalVariable

        y = causify(x) do x
            x < 0.5 ? "Small" : "Biiiig"
        end
        @test y isa CausalVariable

        f = causify(x) do x
            t -> t*x
        end
        final_value = resolve!(f)(10)
        @test final_value == 10 * getvalue(x)

        y_typed = causify(String, x) do x
            x < 0.5 ? "Small" : "Biiiig"
        end
        @test eltype(y_typed) <: String

        a = causify(Normal())
        b = causify(Normal())

        c = @causify a + b

        @test resolve!(c) == resolve!(a) + resolve!(b)

        causalconst = causify(() -> 10)
        @causify begin
            const1 = 15
            const2 = 25
            causal = causalconst * 2
            causalcomplex = causal + const1 + const2 + causalconst^2
        end

        @test const1 == 15
        @test const2 == 25
        @test causalconst isa CausalVariable{Int}
        @test causal isa CausalVariable{Int}
        @test causalcomplex isa CausalVariable{Int}

        resolve!(causalcomplex)

        @test getvalue(causalcomplex) == getvalue(causal) + const1 + const2 + getvalue(causalconst)^2
    end

    @testset "Getting and setting values recursively" begin
        x = causify(Uniform(0,1))
        y = causify(x -> x^2, x)
        ϵ = causify(Uniform(-0.2,0.2))
        z = causify(x, y, ϵ) do x, y, ϵ
            x + y + x*y + ϵ
        end

        refresh!(z) # z and all dependencies become unknown
        @test isunknown(x) && isunknown(y) && isunknown(ϵ) && isunknown(z)

        value = resolve!(z) # z's function and all dependencies resolve.
        @test resolve!(z) == resolve!(z) # z will no longer change
        @test isknown(x) && isknown(y) && isknown(ϵ) # all dependencies known

        invalidate!(z, x)
        @test isunknown(x) && isunknown(y) && isunknown(z) # the pathways between x and z are invalidated
        @test isknown(ϵ) # but the values which did not depend on x are left alone

        # either z or a dependency of z is known (ϵ is), so this sample would not be fresh
        @test_throws "You cannot call" simulate(z)

        simulate!(z) # will run in all circumstances
        simulate!(z) # a totally fresh, different answer
        @test isknown(z) # z is currently known

        refresh!(z) # so let's make it unknown

        zsimulation = simulate(100, z)
        @test zsimulation isa Vector
        @test length(zsimulation) == 100

        # can simulate multiple variables together, and destructure data in one line
        zvals, yvals = simulate(100, z, y)
        @test length(zvals) == length(yvals) == 100

        df = DataFrame(
            collect(simulate(100, z, x, y, ϵ)), # just collect your simulations ...
            [:z, :x, :y, :epsilon] # and name them
        )
        @test df isa DataFrame
        @test size(df, 1) == 100

        z_vals_given_do_x = simulate(1000, z) do
            setvalue!(x, 5)
        end

        avg_z_given_do_x = sum(z_vals_given_do_x) / length(z_vals_given_do_x)
        # x pinned to 5 on every draw -> y = x^2 = 25 deterministically; only ϵ varies and
        # averages to 0 (ϵ ~ Uniform(-0.2, 0.2)), so z averages to 5 + 25 + 5*25 = 155
        @test isapprox(avg_z_given_do_x, 155; atol = 0.5)
    end

    @testset "Causal Analysis" begin
        u = causify(Normal(0, 1))   # unobserved background noise
        x = causify(Uniform(0, 5))  # the variable we're interested in explaining / intervening on

        y = causify(x, u) do x, u
            2x + u
        end

        @testset "Rung 1: Association" begin
            yvals, xvals = simulate(1000, y, x)
            average_y = sum(yvals) / length(yvals)
            # E[y] = 2*E[x] + E[u], x ~ Uniform(0,5) so E[x] = 2.5, E[u] = 0
            @test isapprox(average_y, 2*2.5; atol = 0.5)
        end

        @testset "Rung 2: Intervention" begin
            # do(x = 3): x is forced to 3 on every draw; u is still left free to vary.
            y_given_do_x = simulate(1000, y) do
                setvalue!(x, 3)
            end
            average_y_given_do_x = sum(y_given_do_x) / length(y_given_do_x)
            @test isapprox(average_y_given_do_x, 2*3; atol = 0.5)
        end

        @testset "Rung 3: Counterfactuals" begin
            refresh!(y)
            factual_y, factual_x, factual_u = resolve!(y, x, u) # facts have been gathered

            invalidate!(y, x) # forget everything that happened between x and y (inclusive of both)
            setvalue!(x, factual_x + 1)
            counterfactual_y = resolve!(y) # recompute y, re-using the SAME u

            @test getvalue(u) == factual_u # u was never disturbed
            @test counterfactual_y ≈ factual_y + 2 # by definition of y
        end
    end

    @testset "Faster sampling with Population" begin
        x = causify(Normal(0, 1))

        n = 1_000 # shrunk from the docs' 100_000 purely for test speed; the point (parallel sampling) doesn't depend on the exact count
        pop = population(n, x)    # k defaults to Threads.nthreads()
        samples = resolve!(pop)   # a Vector{Float64} of n independent draws, in parallel

        @test length(samples) == n

        fresh_samples = simulate!(pop) # refresh! + resolve!, in one call
        @test length(fresh_samples) == n
        @test isknown(pop)
    end

end
