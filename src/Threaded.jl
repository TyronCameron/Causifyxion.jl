
#─────────────────────────────────────────────────────────────────────────────#
# Dynamic leafbatches
#─────────────────────────────────────────────────────────────────────────────#
    # Kahn's algorithm, but a node is released when its children are *done*, not when they are taken.
    # The graph is the part of the DAG reachable through `connector`, mapped once up front.
    # Edges are linked lists up to parents (as in Taproots' BottomupFrontier): `firstparent[k]` is node k's
    # first edge (0 for none), `edgeparent[e]` is where edge `e` leads and `nextedge[e]` is the next edge.
    # `pending[k]` counts the connected children of node k which are not yet done. It is atomic so that
    # `markdone!` can be called from many tasks at once.

struct DynamicLeafbatches{N}
    nodes::Vector{N}
    pending::Vector{Threads.Atomic{Int}}
    firstparent::Vector{Int}
    edgeparent::Vector{Int}
    nextedge::Vector{Int}
end

function DynamicLeafbatches(roots; connector)
    nodes = collect(preorder(roots...; connector))
    n = length(nodes)
    frontier = DynamicLeafbatches(nodes, [Threads.Atomic{Int}(0) for _ in 1:n], zeros(Int, n), sizehint!(Int[], n), sizehint!(Int[], n))
    index = IdDict{eltype(nodes), Int}(node => k for (k, node) in enumerate(nodes))
    for (k, node) in enumerate(nodes)
        for child in children(node)
            connector(node, child) || continue
            c = index[child]
            push!(frontier.edgeparent, k)
            push!(frontier.nextedge, frontier.firstparent[c])
            frontier.firstparent[c] = length(frontier.edgeparent)
            frontier.pending[k][] += 1
        end
    end
    return frontier
end

Base.length(frontier::DynamicLeafbatches) = length(frontier.nodes)

# The first batch: every node with no pending children.
firstbatch(frontier::DynamicLeafbatches) = findall(pending -> pending[] == 0, frontier.pending)

# Marks node `k` as done and calls `onready(parent)` for each parent that `k` was the last pending child of.
# Each parent is released exactly once, however many tasks call this concurrently.
function markdone!(onready, frontier::DynamicLeafbatches, k::Int)
    edge = frontier.firstparent[k]
    while edge != 0
        parent = frontier.edgeparent[edge]
        if Threads.atomic_sub!(frontier.pending[parent], 1) == 1 onready(parent) end
        edge = frontier.nextedge[edge]
    end
end

#─────────────────────────────────────────────────────────────────────────────#
# Threaded resolve!
#─────────────────────────────────────────────────────────────────────────────#
    # Each task resolves a node, then releases its parents. The first released parent is resolved by the same
    # task and the rest get tasks of their own, so a chain runs in one task with no hand-offs between threads.
    # `inflight` counts running tasks; the calling task holds one count while it seeds the first batch, so the
    # count cannot hit zero before every first-batch task exists.

"""
    resolve!(::Threaded, causalvariables...)

Like `resolve!(causalvariables...)`, but resolves independent unknown nodes concurrently.
An unknown node starts as soon as its last unknown dependency resolves, on its own task when there is other work in flight.
If a resolver throws, nothing new starts, the running nodes finish, and the first exception is rethrown.
"""
function resolve!(::Threaded, causalvar::NTuple{N,AbstractCausalVariable}) where N
    Threads.nthreads() == 1 && return resolve!(causalvar)
    roots = filter(isunknown, collect(AbstractCausalVariable, causalvar))
    isempty(roots) && return resolve!(causalvar)
    frontier = DynamicLeafbatches(roots; connector = (parent, child) -> isunknown(child))
    length(frontier) <= 1 && return resolve!(causalvar)

    inflight = Threads.Atomic{Int}(1)
    failed = Threads.Atomic{Bool}(false)
    failure = Ref{Any}(nothing)
    failurelock = ReentrantLock()
    finished = Channel{Nothing}(1)

    function run!(k)
        while true
            try
                _resolve_single_node!(frontier.nodes[k])
            catch e
                lock(failurelock) do
                    failure[] === nothing && (failure[] = e)
                end
                failed[] = true
                break
            end
            failed[] && break
            next = 0
            markdone!(frontier, k) do parent
                if next == 0
                    next = parent
                else
                    Threads.atomic_add!(inflight, 1)
                    Threads.@spawn run!(parent)
                end
            end
            next == 0 && break
            k = next
        end
        Threads.atomic_sub!(inflight, 1) == 1 && put!(finished, nothing)
    end

    ready = firstbatch(frontier)
    for k in Iterators.drop(ready, 1)
        Threads.atomic_add!(inflight, 1)
        Threads.@spawn run!(k)
    end
    run!(first(ready)) # uses the calling task's count
    take!(finished)
    failure[] === nothing || throw(failure[]) # same exception type as Serial()
    return resolve!(causalvar) # everything is known now; this only reads the values
end
resolve!(strategy::Threaded, causalvar::AbstractCausalVariable...) = resolve!(strategy, causalvar)
