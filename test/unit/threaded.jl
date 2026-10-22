
@testset "Threaded resolve" begin
    @testset "matches the graph's own arithmetic" begin
        x = causify(Normal(0,1))
        a = @causify x + 1
        b = @causify x * 2
        c = @causify a + b

        value = resolve!(Threaded(), c)
        @test value == getvalue(a) + getvalue(b)
        @test getvalue(a) == getvalue(x) + 1
        @test getvalue(b) == getvalue(x) * 2
        @test resolve!(Threaded(), c) == value # cached, like Serial
    end

    @testset "each shared dependency resolves once" begin
        calls = Threads.Atomic{Int}(0)
        x = causify(() -> (Threads.atomic_add!(calls, 1); rand()))
        branches = [causify(v -> v + i, x) for i in 1:16]
        total = causify((vs...) -> sum(vs), Float64, branches...)

        resolve!(Threaded(), total)
        @test calls[] == 1
        @test getvalue(total) ≈ 16 * getvalue(x) + sum(1:16)
    end

    @testset "only unknown nodes resolve" begin
        x = causify(Normal(0,1))
        a = @causify x + 1
        b = @causify a * 2
        setvalue!(x, 1.0)
        @test resolve!(Threaded(), b) == 4.0
        @test getvalue(x) == 1.0

        setvalue!(a, 10.0); setunknown!(b)
        @test resolve!(Threaded(), b) == 20.0
    end

    @testset "tuple roots share one draw" begin
        x = causify(Normal(0,1))
        a = @causify x + 1
        b = @causify x * 2
        va, vb = resolve!(Threaded(), a, b)
        @test va - 1 ≈ vb / 2
        @test resolve!(Threaded(), (a,)) == va
    end

    @testset "errors propagate with their own type" begin
        x = causify(() -> 1.0)
        bad = causify(v -> throw(DomainError(v)), Float64, x)
        top = @causify bad + x
        @test_throws DomainError resolve!(Threaded(), top)
        @test isunknown(top)
    end

    @testset "simulate! and simulate take a strategy" begin
        x = causify(Uniform(0,1))
        y = @causify x^2
        xs, ys = simulate!(Threaded(), 20, x, y)
        @test xs .^ 2 == ys

        rigged = simulate!(Threaded(), x, y) do
            setvalue!(x, 0.5)
        end
        @test rigged == (0.5, 0.25)

        refresh!(y)
        @test length(simulate(Threaded(), 5, y)) == 5
        @test isunknown(y)
        @test simulate!(Serial(), y) == getvalue(y)
    end

    @testset "Population as a dependency" begin
        x = causify(() -> 1.0)
        pop = population(10, x; k = 2)
        total = causify(sum, pop)
        @test resolve!(Threaded(), total) == 10.0
        refresh!(total)
        @test resolve!(total) == 10.0
    end
end
