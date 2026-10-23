include(joinpath(@__DIR__, "benchmark_setup.jl"))

function profile_test(n, f, example)
    try
        for i in 1:n
            f(example)
        end
    catch e
    end
end

function single_flame_graph(impl, sit, n = 10_000)
    example = get_func(:init, sit)()
    func = get_func(impl, sit)
    profile_test(10, func, example)
    @profview profile_test(n, func, example)
end


single_flame_graph(:causifyxion, :deep_pipeline)
