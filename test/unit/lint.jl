using ExplicitImports: test_explicit_imports
using JET: JET

#─────────────────────────────────────────────────────────────────────────────#
# Static analysis
#─────────────────────────────────────────────────────────────────────────────#

@testset "ExplicitImports" begin
    # Base.RefValue and Base.promote_op are the usual ways to name a Ref's type and an inferred
    # return type, they just aren't marked public
    test_explicit_imports(Causifyxion; all_qualified_accesses_are_public = (; ignore = (:RefValue, :promote_op)))
end

# `@sum_type` generates a branch referring to `THIS_SHOULD_BE_UNREACHABLE`, which SumTypes
# leaves undefined on purpose so that reaching it errors
is_sumtypes_sentinel(report) = report isa JET.UndefVarErrorReport && report.var isa GlobalRef && report.var.name === :THIS_SHOULD_BE_UNREACHABLE

# JET's analysis shifts with each Julia release, so only hold the package to it on the current stable release
if VERSION >= v"1.12" && isempty(VERSION.prerelease)
    @testset "JET" begin
        result = JET.report_package(Causifyxion; target_modules = (Causifyxion,), toplevel_logger = nothing)
        reports = filter(!is_sumtypes_sentinel, JET.get_reports(result))
        isempty(reports) || display(result)
        @test isempty(reports)
    end
end
