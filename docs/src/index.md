# Causifyxion.jl

## Intro

Causifyxion is a library to help create and manage causally-related variables. This library is different from most other libraries because it focuses on variables first (in particular, only thereafter tying in the concept of a distribution). 

Causifyxion helps with:

- Setting up functions which run when needed but whose results are otherwise cached.
- Tracking dependencies between variables. 
- Setting up random, sampleable variables from a `Distribution`, or any other sampleable method. 

The original intention behind this package was to build a statistical (random) library with a sampling- or variable-first approach. However, the naming in this package has been kept general to facilitate thinking in a broader scope. As such, there is no requirement that any variable needs to come from a probabilistic distribution. 

The principle is straightforward: you create a variable by specifying how to calculate it, and you specify the dependencies. These variables need not be numbers -- they can be anything, including functions or even CausalVariables themselves. At its simplest we might have:

```julia
using Dates
x = causify() do # `x` is "Yes" in the first half a minute, and "No" otherwise
	Dates.second(now()) < 30 ? "Yes" : "No"
end 

@assert x isa CausalVariable 
@assert eltype(x) <: String
```

Up to this point, `x` is just a container for a mechanism to sample the value. It has no inherent value itself yet. Indeed if we try to look inside the variable, we get an error:

```julia
getvalue(x) # throws a `ValueUnknownError`
```

Instead we can resolve the value of the variable by executing the function inside it:

```julia
underlying_value = resolve!(x) # returns either "Yes" or "No"
```

`resolve!` also sets the value of `x`, so that:

```julia
@assert getvalue(x) === underlying_value
```

Calling `resolve!` repeatedly will yield the exact same result, even if 30 seconds passes, because the resolved value is stored. We can restore a fresh state on `x` by using: 

```julia
refresh!(x)
new_underlying_value = resolve!(x) # returns a new value 
```

This is not so useful on its own. We could simply memoise the function. It starts to get useful when we create Directed Acyclic Graphs (DAG) of `CausalVariables`. For example:

```julia
using Distributions
x = causify(Normal(10,3))
y = causify(Uniform(0,1))

z = causify(x, y) do x, y 
	length(x) * 500 + y 
end 

@assert eltype(z) <: Float64 # type stability preserved

@assert resolve!(z) == length(getvalue(x)) * 500 + getvalue(y)
```

When I call `resolve!(z)`, it will act on the entire dependency tree (i.e. recursively) of `z`. Same thing when I call `refresh!`. 
`resolve!`ing once might not be enough. You might wish for many of them. In that case, you can `simulate!`: 

```julia
refresh!(z) 

xvals, yvals, zvals = simulate(10, x, y, z) # get back a tuple of data you can easily destructure

# or turn your data into a DataFrame
using DataFrames
df = DataFrame(collect(simulate(10, x, y, z)), [:x, :y, :z])
```

It's also possible to invalidate all downstream caches between a parent and an invalid cache item recursively (but leave every dependency of `x` intact) as follows: 

```julia
resolve!(z) # ensure we have some values
invalidate!(z, x) # invalidate all causal vars between `z` and `x` (taking every possible route to get there). If `z` depends on all of `x`'s upstream consumers, then all upstream consumers will be set unknown. 

@assert isunknown(x)
@assert isunknown(z)
@assert isknown(y)
```

It is crucial that this package mutates the state of Causal Variables, and variables continue to have the same value until they are set as unknown. Used incorrectly, this is can cause spooky action at a distance. Treat the `!` functions as recursive mutations in this package. 


## Getting and setting single values

You can get and set the value of Causal Variables: 


```julia
causalvar = causify() do 
    rand()
end 

setvalue!(causalvar, 10.0) # can set the value
getvalue(causalvar) # can get the value 10.0
```

You can check whether a Causal Variable is known or unknown:

```julia
@assert isknown(causalvar) == !isunknown(causalvar) == true
```

And you can set it back to unknown at any time

```julia
setunknown!(causalvar)
@assert isunknown(causalvar)
```

Key warning: if a value is unknown and you attempt to get its value, it will throw an error. 

```julia
getvalue(causalvar) # throws error
```

If you would rather rebuild the answer than error, it is advisable to use `resolve!` (see below) instead.

## Creating Causal Variables 

One of the key benefits of this package is that you can create a CausalVariable for anything. 

Want a random number? Sure! 

```julia
x = causify(Uniform(0,1))
```

Want a random string? No problem. 

```julia
y = causify(x) do x
    x < 0.5 ? "Small" : "Biiiig"
end 
```

Want a random function that's dependent on `x`? Of course. 

```julia
f = causify(x) do x
    t -> t*x
end 

final_value = resolve!(f)(10)
```

All of this preserves type stability. If you encounter a situation where you are suddenly getting a `CausalVariable{Any}`, you can help it by supplying a type as the first argument. 
As such, it's perfectly valid to write:

```julia
y = causify(String, x) do x
    x < 0.5 ? "Small" : "Biiiig"
end 
```

In many circumstances, however, the type inference here is not the problem. The problem may be type instability in the lambda function passed to `causify` or a missing dependency, or similar. Check these things before supplying a type. Also be aware that if you get the type wrong, it will fail when you attempt to `resolve!` the causal variable, and it may not fail at construction of the causal variable.

Finally, I wanted to present a macro version of `causify`. It is not type stable in the same way as the function version, but it sure is convenient. You can write:

```julia
a = causify(Normal())
b = causify(Normal())

c = @causify a + b 

@assert resolve!(c) == resolve!(a) + resolve!(b)
```

This macro has 4 rules: 

1. If used on an expression such as `@causify a + b`, it will create an expression similar to (not exactly the same as) `causify((a,b) -> a + b, a, b)`. 
2. If used on an assignment expression such as `@causify c = a + b`, that is the same as using it after the assignment operator, so `c = @causify a + b`. 
3. If used on a block such as a `begin ... end` clause, a `@causify` will be propagated down to each expression inside the block. 
4. You can pass certain settings as the first arguments of the macro. At the moment only one setting is available, which is `:constants` which will allow you to not skip over lines where there are no causal variables present. 

Advanced usage -- I can create an entire dependency tree with basically no boilerplate or cognitive overhead.

```julia
causalconst = causify(Normal())
@causify begin 
    const1 = 15
    const2 = 25
    causal = causalconst * 2
    causalcomplex = causal + const1 + const2 + causalconst^2
end 

@assert const1 == 15 
@assert const2 == 25
@assert causalconst isa CausalVariable{Float64}
@assert causal isa CausalVariable # type inference lost here
@assert causalcomplex isa CausalVariable

resolve!(causalcomplex)

@assert getvalue(causalcomplex) == getvalue(causal) + const1 + const2 + getvalue(causalconst)^2
```

## Getting and setting values recursively

Let's set up some variables:

```julia
x = causify(Uniform(0,1))
y = causify(x -> x^2, x)
ϵ = causify(Uniform(-0.2,0.2))
z = causify(x, y, ϵ) do x, y, ϵ
    x + y + x*y + ϵ
end
```

To recursively set all variables as `Unknown`, you can use:

```julia
refresh!(z) # z and all dependencies become unknown
```

To recursively work out the values of all the variables, you can use:

```julia
value = resolve!(z) # z's function and all dependencies resolve. z now has a value
@assert resolve!(z) == resolve!(z) # z will no longer change until it is set unknown
@assert isknown(x) && isknown(y) && isknown(ϵ) # all values underneath also calculated (if unknown)
```

You can also set some paths to unknown (helpful for cache invalidation):

```julia
invalidate!(z, x)
@assert isunknown(x) && isunknown(y) && isunknown(z) # the pathways between `x` and `z` are invalidated
@assert isknown(ϵ) # but the values which did not depend on `x` are left alone
```

You can also use `refresh!` and `resolve!` together for simulation purposes. Doing both of these is called `simulate!`. 

- `simulate!` first refreshes all variables, and then resolves them. You are left with values inside variables you can inspect.
- `simulate` only works on unknown variables, as otherwise it would change global state. If all variables are known, it then resolves all values and then refreshes them, leaving everything in a perfectly unknown position. 

```julia
simulate(z) # error -- either `z` or a dependency of `z` is known, so this sample would not be fresh. 

simulate!(z) # Will happily change state of the variables, including setting them to unknown. 
simulate!(z) # a totally fresh, different answer

@assert isknown(z) # `z` is currently known 

refresh!(z) # so let's make it unknown

# Now let's get a bunch of simulations:

zsimulation = simulate(100, z)
@assert zsimulation isa Vector

# Can simulate multiple variables together, and destructure data in one line
zvals, yvals = simulate(100, z, y)

# Also support for putting this into a DataFrame for further analysis
using DataFrames

df = DataFrame(
    collect(simulate(100, z, x, y, ϵ)), # just collect your simulations ... 
    [:z, :x, :y, :epsilon] # and name them
)
```

Sometimes you might want to investigate the downstream causal relationship between two variables in our DAG. For example, we might wish to investigate how changing `x` causes `z` to change. In that case, we can still use `simulate` (or `simulate!`) with an intervention function. For example, let's say that we can control the variable `x` and that we wish to see how `z` might look if we set it to the value 5. 

```julia
z_vals_given_x = simulate(1000, z) do 
    setvalue!(x, 5.0)
end 

avg_z_given_x = sum(z_vals_given_x) / length(z_vals_given_x)
```

## Causal Analysis

Judea Pearl's "Ladder of Causation" describes three distinct levels of causal reasoning:
**association** (what do we observe?), **intervention** (what if we *do* something?), and
**counterfactuals** (what *would* have happened, given what we know actually happened?).
Causifyxion's variable-first design makes each rung a direct, natural translation of the
corresponding API call.

A small causal model to use throughout this section:

```julia
using Distributions

u = causify(Normal(0, 1))   # unobserved background noise
x = causify(Uniform(0, 5))  # the variable we're interested in explaining / intervening on

y = causify(x, u) do x, u
    2x + u
end
```

### Rung 1: Association (seeing)

The first rung is just observing the system as it naturally unfolds. This is exactly
`simulate!`/`simulate`:

```julia
observed_y = simulate!(y)              # one fresh, fully natural observation

refresh!(y)                            # simulate (no !) requires a fully unknown start
yvals = simulate(1000, y)              # a sample of natural observations
average_y = sum(yvals) / length(yvals)
```

Both `x` and `u` are left free to vary according to their own mechanisms here, exactly as
they would "in the wild".

### Rung 2: Intervention (doing)

The second rung asks what happens if we reach in and force a variable to a value, severing
it from its own mechanism -- Pearl's `do(X = x)`. This is the intervention-function form of
`simulate!`/`simulate`:

```julia
# do(x = 3): x is forced to 3 on every draw; u is still left free to vary.
y_given_do_x = simulate(1000, y) do
    setvalue!(x, 3.0)
end
average_y_given_do_x = sum(y_given_do_x) / length(y_given_do_x)
```

This is *not* the same as conditioning on having observed `x == 3` (a Rung-1 question,
answered by filtering natural observations) -- here `x` never had a chance to be anything
else, on any draw.

### Rung 3: Counterfactuals (imagining)

The third rung asks: given that we *observed* a particular outcome (and therefore a
particular, now-fixed background state of the world), what would that outcome have been had
one variable been different -- with everything else about that same world held fixed? This
needs Pearl's "abduction" then "action": resolve once to fix the background to the values
that actually produced what we saw, then change the variable of interest and recompute
*without* letting the background change too.

**Approach A -- mutate in place with `setvalue!`:**

```julia
refresh!(y)
factual_y = resolve!(y)                    # observe the world -- fixes x and u
factual_x, factual_u = getvalue(x), getvalue(u)

setvalue!(x, factual_x + 1)                # action: what if x had been one more than it was?
setunknown!(y)                 # forget y's cached (factual) value so it recomputes
counterfactual_y = resolve!(y)             # recompute y, re-using the SAME u

@assert getvalue(u) == factual_u            # the background noise was never disturbed
@assert counterfactual_y ≈ factual_y + 2    # y = 2x + u, so +1 to x means +2 to y
```

`setvalue!` doesn't care whether `x` was known or unknown, so it can overwrite the factual
value directly. `resolve!` only recomputes a variable if it's currently `Unknown` though, so
`y`'s own stale cached (factual) value has to be cleared too -- here with `setunknown!`, since
`x` and `y` are directly connected. For a response several steps downstream of the variable
you're intervening on, `invalidate!(y, x)` clears every node strictly between `x`
and `y`; note it leaves `y` itself untouched too, so pair it with `setunknown!(y)` the same way.
(`setunknown!` and `invalidate!` are internal helpers, not exported -- call them as
`setunknown!`/`invalidate!`, or `import Causifyxion: setunknown!,
invalidate!` once if you'd rather not qualify them every time.)

**Approach B -- branch off a fresh world with `replicate`:**

`replicate` doesn't destroy your factual observation: it builds an independent copy of the
dependency tree, sharing only the nodes you name to `keep`.

```julia
refresh!(y)
factual_y = resolve!(y)                    # observe/abduct, same as above

y_cf = replicate(y, u)         # fresh, unknown copies of x and y; u is shared
x_cf, u_shared = y_cf.dependencies

@assert u_shared === u                     # same background noise object
@assert x_cf !== x                         # independent copy of x

setvalue!(x_cf, getvalue(x) + 1)           # the same counterfactual action as Approach A
counterfactual_y2 = resolve!(y_cf)

@assert counterfactual_y2 ≈ factual_y + 2       # same +1-to-x => +2-to-y relationship
@assert isknown(y) && getvalue(y) == factual_y  # the original, factual `y` is untouched
```

Approach B is especially convenient when comparing several counterfactual scenarios against
the same factual observation side by side, since none of them interfere with each other or
with the original.

## Faster sampling with `Population`

When you need a *large* number of independent, identically-distributed samples of a single
`CausalVariable` -- e.g. Rung-1 questions like estimating `E[Y]`, or building an empirical
distribution -- `simulate(n, causalvar)` resolves the whole dependency tree fresh,
sequentially, `n` times. For large `n`, `population` is a faster alternative: it builds `k`
independent replicas of your variable up front and spreads the `n` draws across them in
parallel.

```julia
x = causify(Normal(0, 1))

pop = population(100_000, x)      # k defaults to Threads.nthreads()
samples = resolve!(pop)           # a Vector{Float64} of 100,000 independent draws, in parallel

@assert length(samples) == 100_000
```

Like any other `CausalVariable`, a `Population` caches its resolved value until `refresh!`ed,
and works with `simulate!`/`simulate` too:

```julia
fresh_samples = simulate!(pop)    # refresh! + resolve!, in one call
```

`k` only buys real parallelism if Julia itself is started with multiple threads
(`julia -t auto`); pass it explicitly with `population(n, x; k = 8)` to control it directly.

## Useful features of sampling-first

Sampling is a simple procedure, and by expressing our variables through sampling mechanisms, capturing their causal dependencies, we arrive at a very natural way to model the real world. We can describe plain and simple relationships between variables.

Besides the intuitiveness of writing in this fashion, this package thrives in circumstances where resolving values is expensive, and data must be cached and clear rules must govern when it is and is not discarded. 

On the other hand, it also thrives when resolving values is cheap and we can approach the infinite data limit. In those cases, sampling makes sense, rather than doing the complicated work of dealing with distributions. 

That doesn't mean that this philosophy is the only (or best) view of sampling values. In particular, it has limitations: 

- Distributions are thrown away / obscured and only the mechanism of sampling is preserved
- 


