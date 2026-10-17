---
vexid: implement-importance-sampler-1
vextype: task
description: Implement an importance sampler
created: "2026-10-12 21:10:23"
modified: "2026-10-12 21:10:23"
status: todo
---

On the topic of creating new types of CausalVariable which inherit from AbstractCausalVariable

```julia
struct Resampler
    sample
    weights 
end 

# One option: 
# Temporarily swap in a Resampler inside a resolver to achieve importance sampling
# Basically, do rejection sampling with fewer rejections. 

# Originally I thought it may be necessary to make it inherit from AbstractCausalVariable 
# But now I am not too sure. 
```