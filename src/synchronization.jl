isset(event::EventCondition) = event.active[]
value(event::EventCondition) = event.value[]
isset(event::Nothing) = false

reset(event::EventCondition) = setevent(event; active=false, value=nothing)

"""Set state of an EventCondition. Not multi-thread safe."""
function setevent(event::EventCondition;
    active::Bool=false, value::Any=nothing
)
    # not MT safe.
    event.active[] = active
    event.value[] = value
    return event
end

"""
Create or retrieve the spacecraft's EventCondition, and set it state.
Locks spacecraft's event storage during access.
"""
function setevent(sp::Spacecraft, sym::Symbol;
    active::Bool=false, value::Any=nothing
)
    event = nothing
    acquire(sp, :events) do
        if sym ∉ keys(sp.events)
            event = EventCondition(active, value)
            sp.events[sym] = event
        else
            event = sp.events[sym]
            event.active[] = active
            event.value[] = value
        end
    end
    @assert !isnothing(event)
    return event
end

"""
Set state of an EventCondition.
Locks spacecraft's event storage during access.
"""
function setevent(sp::Spacecraft, event::EventCondition;
    active::Bool=false, value::Any=nothing
)
    acquire(sp, :events) do
        event.active[] = active
        event.value[] = value
    end
    return event
end

"""
Retrieve event, but don't create it.
To create it if it doesn't exist, use `setevent`.
"""
function getevent(sp::Spacecraft, sym::Symbol)
    event = nothing
    acquire(sp, :events) do
        if sym ∈ keys(sp.events)
            event = sp.events[:sym]
        end
    return event
end

function wait(sp::Spacecraft, sym::Symbol;
    retroactive::Bool=true, once::Bool=false
)
    setevent(sp, sym)
    event::EventCondition = sp.events[sym]
    if retroactive && event.active[]
        once ? wait(sp, :never) : return event.value[]
    end
    Base.wait(event.cond)
end

function notify(event::EventCondition, value=nothing;
    name::String="Unknown", all::Bool=true, error::Bool=false
)
    setevent(event; active=active, value=value)
    count = notify(event.cond, value; all=all, error=error)
    @debug "`$name` has notified $count listeners" _group=:event
    return count
end

function notify(sp::Spacecraft, sym::Symbol, value=nothing;
    name::String="", all::Bool=true, error::Bool=false
)
    event = setevent(sp, sym; active=active, value=value)
    count = notify(event.cond, value; all=all, error=error)
    @debug "`$name` has notified $count listeners via $sym" _group=:event
    return count
end

function notify(sp::Spacecraft, event::EventCondition, value=nothing;
    name::String="", all::Bool=true, error::Bool=false
)
    event = setevent(sp, event; active=active, value=value)
    count = notify(event.cond, value; all=all, error=error)
    @debug "`$name` has notified $count listeners" _group=:event
    return count
end

"""
    acquire(sp, sym)

Release a semaphore of the Spacecraft identified by `sym`.
"""
function Base.release(sp::Spacecraft, sym::Symbol)
    sym ∉ keys(sp.semaphore) && return
    Base.release(sp.semaphore[sym])
end

"""
    acquire(sp, sym, [limit])

Acquire or create a semaphore of the Spacecraft identified by `sym`.
"""
function Base.acquire(sp::Spacecraft, sym::Symbol, limit::Integer=1)
    Base.acquire(sp.semaphore[:semaphore]) do
        if sym ∉ keys(sp.semaphore)
            sp.semaphore[sym] = Base.Semaphore(limit)
        end
    end
    Base.acquire(sp.semaphore[sym])
end

"""
    acquire(f, sp, sym, [limit])

Acquire or create a semaphore of the Spacecraft identified by `sym`,
execute function `f` and then release the semaphore.
"""
function Base.acquire(f::Function, sp::Spacecraft, sym::Symbol, limit::Integer=1)
    try
        acquire(sp, sym, limit)
        return f()
    finally
        release(sp, sym)
    end
end
