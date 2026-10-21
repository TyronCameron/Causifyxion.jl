using ExplicitImports: test_explicit_imports
using JET: JET

#─────────────────────────────────────────────────────────────────────────────#
# Static analysis
#─────────────────────────────────────────────────────────────────────────────#

@testset "ExplicitImports" begin
    test_explicit_imports(Causifyxion; all_qualified_accesses_are_public = (; ignore = (:RefValue, :promote_op)))
end

is_sumtypes_sentinel(report) = report isa JET.UndefVarErrorReport && report.var isa GlobalRef && report.var.name === :THIS_SHOULD_BE_UNREACHABLE

if VERSION >= v"1.12" && isempty(VERSION.prerelease)
    @testset "JET" begin
        result = JET.report_package(Causifyxion; target_modules = (Causifyxion,), toplevel_logger = nothing)
        reports = filter(!is_sumtypes_sentinel, JET.get_reports(result))
        isempty(reports) || display(result)
        @test isempty(reports)
    end
end
