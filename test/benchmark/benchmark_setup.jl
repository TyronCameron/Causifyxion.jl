
using BenchmarkTools
using Causifyxion
using DataFrames
using PrettyTables
using Profile
using JET

implementations::Tuple = (:naive, :causifyxion, :threaded)
situations::Tuple = (
    :deep_pipeline,
    :branching_pipeline,
    :expensive_wide,
    :expensive_chain,
)

module InitFunctions
    using Causifyxion
    for file in readdir(joinpath(@__DIR__, "init"), join = true)
        include(file)
    end
end
import .InitFunctions

module NaiveFunctions
    using Causifyxion
    for file in readdir(joinpath(@__DIR__, "naive"), join = true)
        include(file)
    end
end
import .NaiveFunctions

module CausifyxionFunctions
    using Causifyxion
    for file in readdir(joinpath(@__DIR__, "causifyxion"), join = true)
        include(file)
    end
end
import .CausifyxionFunctions

module ThreadedFunctions
    using Causifyxion
    for file in readdir(joinpath(@__DIR__, "threaded"), join = true)
        include(file)
    end
end
import .ThreadedFunctions

function get_func(implementation, situation)
    if implementation == :init
        @eval InitFunctions.$situation
    elseif implementation == :naive
        @eval NaiveFunctions.$situation
    elseif implementation == :causifyxion
        @eval CausifyxionFunctions.$situation
    elseif implementation == :threaded
        @eval ThreadedFunctions.$situation
    else
        @assert false "No known functions for $implementation"
    end
end

loc(implementation, situation) = length(readlines(joinpath(@__DIR__, string(implementation), string(situation) * ".jl")))

function setup_benchmarkable(situation)
    example = get_func(:init, situation)()
    map(implementations) do implementation
        func = get_func(implementation, situation)
        implementation => @benchmarkable $func($example)
    end |> splat(Dict)
end

default_results(implementation, situation) = (
    loc = loc(implementation, situation),
    time = Inf,
    memory = Inf,
    gctime = Inf,
    allocs = Inf,
)

function run_benchmarkable(situation, benchmarkable)
    results = Dict()
    for (implementation, bench) in benchmarkable
        try
            trial = median(run(bench))
            results[(implementation, situation)] = (
                loc = loc(implementation, situation),
                time = trial.time,
                memory = trial.memory,
                gctime = trial.gctime,
                allocs = trial.allocs,
            )
        catch e
            results[(implementation, situation)] = default_results(implementation, situation)
        end
    end
    return results
end

function setup_and_run_benchmarkable(situation)
    benchmarkable = setup_benchmarkable(situation)
    run_benchmarkable(situation, benchmarkable)
end

function setup_and_run_all_benchmarks()
    all_results = Dict()
    for situation in situations
        @info "Starting $situation. Results:"
        for (key, results) in setup_and_run_benchmarkable(situation)
            @info "\t$key:\n$results"
            all_results[key] = results
        end
    end
    return all_results
end

results_to_table(results) = reduce(implementations, init = DataFrame()) do acc, implementation
    impl_keys = collect(filter(k -> k[1] == implementation, keys(results)))
    df = reduce(impl_keys, init = []) do vec, key
        push!(vec, (benchmark = last(key), implementation = first(key), results[key]...))
    end |> DataFrame
    append!(acc, df)
end

function unpivot_table(df)
    wide = map(implementations) do implementation
        part = select(df[df.implementation .== implementation, :], Not(:implementation))
        rename(name -> name == "benchmark" ? name : "$(name)_$(implementation)", part)
    end
    df = innerjoin(wide...; on = :benchmark)
    order = Dict(s => i for (i, s) in enumerate(situations))
    sort!(df, by = x -> get(order, x, Inf))
end

function table_to_markdown(df)
    pretty_table(String, df, backend=:markdown)
end
