include(joinpath(@__DIR__, "benchmark_setup.jl"))

results = setup_and_run_all_benchmarks()
df = results_to_table(results)
mark = unpivot_table(df) |> table_to_markdown

open(joinpath(@__DIR__, "results.md"), "w") do f
    write(f, mark)
end
