
using Dates

@testset "Docs" begin

    @testset "Intro" begin
        x = causify() do
            Dates.second(now()) <= 30 ? "Yes" : "No"
        end

        @test x isa CausalVariable
        @test eltype(x) <: String

        @test_throws ValueUnknownError getvalue(x)

        underlying_value = resolve!(x)
        @test getvalue(x) === underlying_value

        refresh!(x)
        new_underlying_value = resolve!(x)
        @test new_underlying_value isa String

        x = causify(Normal(10,3))
        y = causify(Uniform(0,1))

        z = causify(x, y) do x, y
            length(x) * 500 + y
        end

        @test eltype(z) <: Float64
        @test resolve!(z) == length(getvalue(x)) * 500 + getvalue(y)

        refresh!(z)
        xvals, yvals, zvals = simulate(10, x, y, z)
        @test length(xvals) == length(yvals) == length(zvals) == 10

        df = DataFrame(collect(simulate(10, x, y, z)), [:x, :y, :z])
        @test df isa DataFrame
        @test size(df, 1) == 10

        resolve!(z)

        invalidate!(z, x)

        @test isunknown(x)
        @test isunknown(z)
        @test isknown(y)
    end

    @testset "Getting and setting single values" begin
        causalvar = causify() do
            rand()
        end

        setvalue!(causalvar, 10.0)
        @test getvalue(causalvar) == 10.0

        @test isknown(causalvar) == !isunknown(causalvar) == true

        setunknown!(causalvar)
        @test isunknown(causalvar)

        @test_throws ValueUnknownError getvalue(causalvar)
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
        @test causalconst isa CausalVariable && eltype(causalconst) === Int
        @test causal isa CausalVariable && eltype(causal) === Int
        @test causalcomplex isa CausalVariable && eltype(causalcomplex) === Int

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

        refresh!(z)
        @test isunknown(x) && isunknown(y) && isunknown(ϵ) && isunknown(z)

        value = resolve!(z)
        @test resolve!(z) == resolve!(z)
        @test isknown(x) && isknown(y) && isknown(ϵ)

        invalidate!(z, x)
        @test isunknown(x) && isunknown(y) && isunknown(z)
        @test isknown(ϵ)

        @test_throws ValueAlreadyKnownError simulate(z)

        simulate!(z)
        simulate!(z)
        @test isknown(z)

        refresh!(z)

        zsimulation = simulate(100, z)
        @test zsimulation isa Vector
        @test length(zsimulation) == 100

        zvals, yvals = simulate(100, z, y)
        @test length(zvals) == length(yvals) == 100

        df = DataFrame(
            collect(simulate(100, z, x, y, ϵ)),
            [:z, :x, :y, :epsilon]
        )
        @test df isa DataFrame
        @test size(df, 1) == 100

        z_vals_given_do_x = simulate(1000, z) do
            setvalue!(x, 5)
        end

        avg_z_given_do_x = sum(z_vals_given_do_x) / length(z_vals_given_do_x)
        @test isapprox(avg_z_given_do_x, 155; atol = 0.5)
    end

    @testset "Causal Analysis" begin
        u = causify(Normal(0, 1))
        x = causify(Uniform(0, 5))

        y = causify(x, u) do x, u
            2x + u
        end

        @testset "Rung 1: Association" begin
            yvals, xvals = simulate(1000, y, x)
            average_y = sum(yvals) / length(yvals)
            @test isapprox(average_y, 2*2.5; atol = 0.5)
        end

        @testset "Rung 2: Intervention" begin
            y_given_do_x = simulate(1000, y) do
                setvalue!(x, 3)
            end
            average_y_given_do_x = sum(y_given_do_x) / length(y_given_do_x)
            @test isapprox(average_y_given_do_x, 2*3; atol = 0.5)
        end

        @testset "Rung 3: Counterfactuals" begin
            refresh!(y)
            factual_y, factual_x, factual_u = resolve!(y, x, u)

            invalidate!(y, x)
            setvalue!(x, factual_x + 1)
            counterfactual_y = resolve!(y)

            @test getvalue(u) == factual_u
            @test counterfactual_y ≈ factual_y + 2
        end
    end

    @testset "Faster sampling with Population" begin
        x = causify(Normal(0, 1))

        n = 1_000
        pop = population(n, x)
        samples = resolve!(pop)

        @test length(samples) == n

        fresh_samples = simulate!(pop)
        @test length(fresh_samples) == n
        @test isknown(pop)
    end

    @testset "Monty Hall" begin
        car = causify(DiscreteUniform(1, 3))
        pick = causify(DiscreteUniform(1, 3))
        host = @causify rand(setdiff(1:3, (car, pick)))
        swap = @causify only(setdiff(1:3, (pick, host)))
        wins = @causify swap == car

        outcomes = resolve!(population(100_000, wins))
        @test isapprox(sum(outcomes) / length(outcomes), 2/3; atol = 0.02)

        saw = @causify pick == 1 && host == 3
        car_behind_2 = @causify car == 2

        outcomes = resolve!(population(100_000, car_behind_2 | saw))
        @test isapprox(sum(skipmissing(outcomes)) / count(!ismissing, outcomes), 2/3; atol = 0.03)
    end

end
