isset(event::EventCondition) = event.active[]
value(event::EventCondition) = event.value[]
isset(event::Nothing) = false

Base.reset(event::EventCondition) = event!(event; active=false, value=nothing)

"""Set state of an EventCondition. Not multi-thread safe."""
function event!(event::EventCondition;
    active::Bool=false, value::Any=nothing
)
    # not MT safe.
    event.active[] = active
    event.value[] = value
    return event
end

"""
Create or modify the spacecraft's EventCondition without notifying it.
Locks spacecraft's event storage during access.
"""
function event!(sp::Spacecraft, sym::Symbol;
    active::Bool=false, value::Any=nothing, create::Bool=true
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
    return event
end

"""
Set state of an EventCondition without notifying it.
Locks spacecraft's event storage during access.
"""
function event!(sp::Spacecraft, event::EventCondition;
    active::Bool=false, value::Any=nothing
)
    acquire(sp, :events) do
        event.active[] = active
        event.value[] = value
    end
    return event
end

"""
Retrieve or create an event.
"""
function event(sp::Spacecraft, sym::Symbol; create::Bool=false)
    event = nothing
    acquire(sp, :events) do
        if sym ∈ keys(sp.events)
            event = sp.events[sym]
        end
    end
    return event
end

function wait(sp::Spacecraft, sym::Symbol;
    retroactive::Bool=true, once::Bool=false
)
    event!(sp, sym)
    event::EventCondition = sp.events[sym]
    if retroactive && event.active[]
        once ? wait(sp, :never) : return event.value[]
    end
    Base.wait(event.cond)
end

function notify(event::EventCondition, value=nothing;
    name::String="Unknown", all::Bool=true, error::Bool=false
)
    event!(event; active=true, value=value)
    count = notify(event.cond, value; all=all, error=error)
    @debug "`$name` has notified $count listeners" _group=:event
    return count
end

function notify(sp::Spacecraft, sym::Symbol, value=nothing;
    name::String="", all::Bool=true, error::Bool=false
)
    event = event!(sp, sym; active=true, value=value)
    count = notify(event.cond, value; all=all, error=error)
    @debug "`$name` has notified $count listeners via $sym" _group=:event
    return count
end

function notify(sp::Spacecraft, event::EventCondition, value=nothing;
    name::String="", all::Bool=true, error::Bool=false
)
    event = event!(sp, event; active=true, value=value)
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

function Base.show(io::IO, event::EventCondition)
    state = isset(event) ? "triggered" : "standby"
    value = isnothing(value) ? "empty" : "stored"
    print(io, "EventCondition ($state, $value)")
end
