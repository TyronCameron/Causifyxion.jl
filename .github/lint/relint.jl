using ReLint: ReLint

const EXCLUDED = [
    "in",
    "haskey",
    "equal",
    "unsafe-logging",
    "unsafe-assert",
    "interpolation in `@warnv_safe_to_log`",
    "TODO",
    "TODO PR",
    "noinline with non-literal/identifier args",
    "RelPath",
    "RelPath split_path",
    "RelPath drop_first",
    "RelPath relpath_from_signature",
    "remove_page",
    "no import RAICode",
    "initializing with `is_local_deployment`",
    "return in anonymous function",
    "@generated",
    "Task",
    "no import",
]

const ADVISORY = [
    "splatting",
    "@inbounds",
    "@sync",
    "@threads",
    "yield",
    "sleep",
    "unlock",
    "ccall",
    "@cfunction",
    "finalizer",
    "isnothing",
]

rule_names = Set(rule.name for rule in ReLint.ALL_RULES)
unknown = setdiff(vcat(EXCLUDED, ADVISORY), rule_names)
isempty(unknown) || error("ReLint no longer has these rules: $(join(unknown, ", "))")

enforced = [rule for rule in ReLint.ALL_RULES if !(rule.name in EXCLUDED) && !(rule.name in ADVISORY)]
advisory = [rule for rule in ReLint.ALL_RULES if rule.name in ADVISORY]

function lint(rules, folders)
    report = ReLint.LintGlobalReport()
    for folder in filter(isdir, folders)
        ReLint.run_lint(folder; result = report, context = ReLint.LintContext(rules))
    end
    return report
end

println("Enforced rules")
failures = lint(enforced, ARGS)
println("\nAdvisory rules")
advice = lint(advisory, ARGS)

failure_count = failures.violations_count + failures.fatal_violations_count + failures.recommendations_count
println("\nReLint: $(failure_count) failure(s), $(advice.recommendations_count) advisory note(s)")
exit(failure_count == 0 ? 0 : 1)
