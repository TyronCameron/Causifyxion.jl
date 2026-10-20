# Runs ReLint over the given folders and fails on any violation.
# ReLint ships RelationalAI's house rules too (`tin`, `thaskey`, `@safe` logging, Jira TODOs, ...),
# so only the rules that make sense outside RAI are enforced. Recommendations are printed but never fail.
# Silence a single line with `# lint-disable-next-line: <rule description>`.
using ReLint: ReLint

const ENFORCED = [
    "show",                          # stray `@show`
    "bare using",                    # `using Foo: names` rather than `using Foo`
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
