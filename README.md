# Causifyxion.jl 

Create causal, sampleable random variables. 

Features:

- Focus on variables, not sampling methods or distributions. (Use `Distributions.jl` to get that stuff).
- Organise the causal (one-way dependency) relationships between variables. 
- Turn any type into a random variable.


## Todo

- Need a nice way to do 

Would be nice to have a register as well so that you can access those nodes at constant time later.

```julia
@causify begin
	config = Dict(...) # useful for how simulations are done ? 
	my_actions = ( # can be varied later in a nice way
		a => 100,
		b => 200
	)
	x = ...
	y = ... 
end 
```

Would also be nice to have something like this 

```yaml

VARIABLE_A:
	defn: VAR_B + VAR_C
	- VAR_B 
	- VAR_C

VARIABLE_B:
	distr: Normal(0,1)

VARIABLE_C:
	const: 500

```


