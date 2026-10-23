
@testset "Simulate / Invalidate" begin

    @testset "invalidate! sets parent too" begin
        x = causify(Uniform(0,1))
        y = causify(x -> x^2, x)
        ϵ = causify(Uniform(-0.2,0.2))
        z = causify(x, y, ϵ) do x, y, ϵ
            x + y + x*y + ϵ
        end

        resolve!(z)
        @test isknown(x) && isknown(y) && isknown(z) && isknown(ϵ)

        invalidate!(z, x)

        @test isunknown(z)
        @test isunknown(y)
        @test isunknown(x)
        @test isknown(ϵ)
    end

    @testset "invalidate! with parent == child" begin
        x = causify(Uniform(0,1))
        y = causify(x -> x^2, x)
        ϵ = causify(Uniform(-0.2,0.2))
        z = causify(x, y, ϵ) do x, y, ϵ
            x + y + x*y + ϵ
        end
        resolve!(z)

        invalidate!(x, x)

        @test isunknown(x)
        @test isknown(y)
        @test isknown(z)
        @test isknown(ϵ)
    end

    @testset "invalidate! finds all routes between parent and child" begin
        a = causify(Uniform(0,1))
        b = causify(a2 -> a2 + 1, a)
        c = causify(a2 -> a2 * 2, a)
        d = causify(b, c) do b2, c2
            b2 + c2
        end

        resolve!(d)
        @test isknown(a) && isknown(b) && isknown(c) && isknown(d)

        invalidate!(d, a)

        @test isunknown(a)
        @test isunknown(b)
        @test isunknown(c)
        @test isunknown(d)
    end

    @testset "setunknown! in isolation" begin
        x = causify(() -> 1.0)
        setvalue!(x, 5.0)
        @test isknown(x)

        @test setunknown!(x) === x
        @test isunknown(x)

        @test_throws ValueUnknownError getvalue(x)

        p = causify(() -> 2.0)
        child = causify(p2 -> p2 * 10, p)
        resolve!(child)
        @test isknown(p) && isknown(child)

        setunknown!(child)
        @test isunknown(child)
        @test isknown(p)
    end

    @testset "invalidate! interacts correctly with resolve!/refresh! afterward" begin
        x = causify(Uniform(0,1))
        y = causify(x -> x^2, x)
        ϵ = causify(Uniform(-0.2,0.2))
        z = causify(x, y, ϵ) do x, y, ϵ
            x + y + x*y + ϵ
        end

        resolve!(z)
        ϵ_val = getvalue(ϵ)

        invalidate!(z, x)
        resolve!(z)

        @test getvalue(ϵ) == ϵ_val
        @test getvalue(z) ≈ getvalue(x) + getvalue(y) + getvalue(x)*getvalue(y) + getvalue(ϵ)

        refresh!(z)
        @test isunknown(ϵ)
    end

end
