using ReLint: ReLint

const ENFORCED = [
    "show",
    "bare using",
    "non-const untyped global",
    "unreachable branch",
    "static threads",
    "initializing with `nthreads`",
    "@async",
    "unsafe_ function",
    "uv",
]
const ADVISORY = collect(keys(ReLint.RECOMMENDATIONS))

rules = [rule for rule in ReLint.ALL_RULES if rule.name in ENFORCED || rule.name in ADVISORY]
missing_rules = setdiff(ENFORCED, [rule.name for rule in rules])
isempty(missing_rules) || error("ReLint no longer has these rules: $(join(missing_rules, ", "))")

report = ReLint.LintGlobalReport()
for folder in filter(isdir, ARGS)
    ReLint.run_lint(folder; result = report, context = ReLint.LintContext(rules))
end
failures = report.violations_count + report.fatal_violations_count
println("\nReLint: $(failures) violation(s), $(report.recommendations_count) recommendation(s) across $(report.files_count) file(s)")
exit(failures == 0 ? 0 : 1)
