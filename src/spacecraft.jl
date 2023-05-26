struct PersistentCondition
    cond::Condition
    active::Ref{Bool}
    value::Ref{Any}
    function PersistentCondition(active::Bool=false, value::Any=nothing)
        new(Condition(), active, value)
    end
end


abstract type AbstractControl end

"""
    ControlChannel <: AbstractControl

A collection of channels for continuous control loops. These channels do not
do anything on their own, and need to be hooked up to control loops.

# Fields
- `engage`: Engage or disengage autopilot.
- `throttle`: Throttle control [0, -1].
- `roll`: Roll control.
- `direction`: Directional vector. Uses on current autopilot's reference frame.
- `rcs`: 3-tuple [-1, 1] values for RCS translation (fore, up, right).
"""
struct ControlChannel <: AbstractControl
    engage::Channel{Bool}
    throttle::Channel{Float32}
    roll::Channel{Float32}
    direction::Channel{NTuple{3,Float64}}
    rcs::Channel{NTuple{3,Union{Missing,Float32}}}
    function ControlChannel(size::Integer=1)
        @debug "Creating control channel" _group=:control
        new(create_control_channels(size)...)
    end
end

function create_control_channels(size::Integer=1)
    e = Channel{Bool}(size)
    t = Channel{Float32}(size)
    r = Channel{Float32}(size)
    d = Channel{NTuple{3,Float64}}(size)
    rcs = Channel{NTuple{3,Union{Missing,Float32}}}(size)
    return (e, t, r, d, rcs)
end

"""
    SubControl(id, cmd, [size])

A wrapper around a control channel with the capability to be turned on and off.

# Fields
- `name`: identifiable name of the control.
- `sink`: ControlChannel of the master control.
- `toggle`: a toggle switch to enable or disable transfer to master channel.
- `...`: identical to ControlChannel channels

# Extra arguments
- `size`: Buffer size for the channel. 1 is recommended.
"""
struct SubControl <: AbstractControl
    name::String
    sink::ControlChannel
    toggle::Ref{Bool}

    engage::Channel{Bool}
    throttle::Channel{Float32}
    roll::Channel{Float32}
    direction::Channel{NTuple{3,Float64}}
    rcs::Channel{NTuple{3,Union{Missing,Float32}}}
    function SubControl(
        name::String,
        sink::ControlChannel,
        toggle=true,
        size::Integer=1
    )
        @info "Creating subcontrol $name" _group=:control
        toggle = Ref(toggle)
        con = new(name, sink, toggle, create_control_channels(size)...)
        @async _transfer(con.engage, sink.engage, toggle, "$name/engage")
        @async _transfer(con.throttle, sink.throttle, toggle, "$name/throttle")
        @async _transfer(con.roll, sink.roll, toggle, "$name/roll")
        @async _transfer(con.direction, sink.direction, toggle, "$name/direction")
        @async _transfer(con.rcs, sink.rcs, toggle, "$name/rcs")
        return con
    end
end

"""
    MasterControl()

Manages a set of SubControls and connects to hardware ControlChannel.

This control itself does not do anything but transfer data.
Hardware control loop should be started in the Spacecraft's side for it to work.

# Fields
- `users`: A list of SubControls.
- `src`: Collectionpoint for SubControls. Ignored when `toggle` is off.
- `sink`: Hardware ControlChannel. Direct access to this channel always works.
- `active`: A stop switch for cutting off all SubControls, regardless of mask.
"""
struct MasterControl
    users::Vector{SubControl}
    src::ControlChannel
    sink::ControlChannel
    toggle::Ref{Bool}
    function MasterControl()
        users = Vector{SubControl}()
        src = ControlChannel(1)
        sink = ControlChannel(1)
        toggle = Ref(true)
        @async _transfer(src.engage, sink.engage, toggle, "master/engage")
        @async _transfer(src.throttle, sink.throttle, toggle, "master/throttle")
        @async _transfer(src.roll, sink.roll, toggle, "master/roll")
        @async _transfer(src.direction, sink.direction, toggle, "master/direction")
        @async _transfer(src.rcs, sink.rcs, toggle, "master/rcs")
        mc = new(users, src, sink, toggle)
        @async _gc(mc, 120)
        return mc
    end
end

disable(con::Union{MasterControl,SubControl}) = con.toggle[] = false
enable(con::Union{MasterControl,SubControl}) = con.toggle[] = true
function enable(f::Function, con::Union{MasterControl,SubControl})
    enable(con)
    try
        return f()
    finally
        disable(con)
    end
end

"Run garbage collection for closed channels. If period is ≤ 0, run once and exit."
function _gc(con::MasterControl, period::Real)
    while isopen(con)
        closed = findall(u -> !isopen(u), con.users)
        deleteat!(con.users, closed)
        period <= 0 && break
        sleep(period)
    end
end

"""
    Spacecraft

Structure representing a spacecraft to be controlled.

# Fields
- `name`: Cached name of the spacecraft. Can be used for namespacing logs.
- `ves`: KRPC Vessel. Most control actions act on this object.
- `parts`: Cached dictionary of spacecraft's parts. Since many parts have
Saving the values here saves the trouble of traversing the part tree.
- `events`: A dictionary for vessel-wide function synchronization.
- `sync`: A dictionary for vessel-wide semaphore synchronization.
- `control`: Master control channel of the spacecraft.
- `ts`: UT timeserver to access global time.
- `met`: MET timeserver to access vehicle's specific mission elapsed time.
Useful for resuming mission from save, as MET is not volatile.
"""
struct Spacecraft
    name::String
    ves::SCR.Vessel
    parts::Dict{Symbol,SCR.Part}
    events::Dict{Symbol,PersistentCondition}
    semaphore::Dict{Symbol,Base.Semaphore}
    control::MasterControl
    ts::Timeserver
    met::Timeserver
end

function Spacecraft(
    conn::KRPC.KRPCConnection,
    ves::SCR.Vessel;
    name = nothing,
    control = MasterControl(),
    ts = Timeserver(),
    met = Timeserver(conn, ves)
)
    name = isnothing(name) ? SCH.Name(ves) : name
    ts.type == "Offline" && @warn "Using offline time server; vessel timing maybe out of sync." _group=:system
    parts = Dict{Symbol,SCR.Part}()
    events = Dict{Symbol,PersistentCondition}(
        :never => PersistentCondition(),
    )
    semaphore = Dict{Symbol,Base.Semaphore}(
        :stage => Base.Semaphore(1),
        :semaphore => Base.Semaphore(1),
        :events => Base.Semaphore(1),
    )
    @async begin
        try
            # if time server closes or gets stop signal,
            # the spacecraft will no longer be controllable.
            wait(met.clients[1])
        finally
            # close the control channels.
            @info "Spacecraft $name has been shut down." _group=:system
            close(control)
            close(met)
        end
    end
    sp = Spacecraft(name, ves, parts, events, semaphore, control, ts, met)
    @info "Hardware control loop starting" _group=:control
    @async _hardware_transfer_engage(sp)
    @async _hardware_transfer_throttle(sp)
    @async _hardware_transfer_roll(sp)
    @async _hardware_transfer_direction(sp)
    @async _hardware_transfer_rcs(sp)
    return sp
end

"""
    subcontrol(mc, name, [size])

Create a new subcontrol unit, register it to the master control loop. The
SubControl is initialized as enabled.
"""
function subcontrol(mc::MasterControl, name::String="untitled", size::Integer=1)
    con = SubControl(name, mc.src, true, size)
    push!(mc.users, con)
    @info "SubControl '$name' has been added" _group=:control
    con
end
subcontrol(sp::Spacecraft, name::String="untitled", size::Integer=1) = subcontrol(sp.control, name, size)

function _transfer(
    from::Channel{T},
    to::Channel{T},
    toggle::Ref{Bool}=Ref(true),
    name::String="untitled"
) where {T}
    try
        @debug "Transfer channel ($name) started" _group=:control
        while true
            value = take!(from)
            toggle[] && put!(to, value)
            yield()
        end
    finally
        @debug "Transfer channel ($name) closed" _group=:control
    end
end

function _hardware_transfer_engage(sp::Spacecraft)
    ap = SCH.AutoPilot(sp.ves)
    try
        while true
            cmd = take!(sp.control.sink.engage)
            if cmd
                @debug "Engage autopilot" _group=:input
                SCH.Engage(ap)
            else
                @debug "Disengage autopilot" _group=:input
                SCH.Disengage(ap)
            end
            yield()
        end
    catch e
        !isa(e, InvalidStateException) && @error "Unexpected loss of engage control for $(sp.name)" _group=:control
    finally
        @debug "Engage loop closed for $(sp.name)" _group=:control
    end
end

function _hardware_transfer_throttle(sp::Spacecraft)
    ctrl = SCH.Control(sp.ves)
    try
        while true
            cmd = take!(sp.control.sink.throttle)
            level = clamp(cmd, 0f0, 1f0)
            @debug "Set throttle level to $level" _group=:input
            SCH.Throttle!(ctrl, level)
            yield()
        end
    catch e
        !isa(e, InvalidStateException) && @error "Unexpected loss of throttle control for $(sp.name)" _group=:control
    finally
        @debug "Throttle loop closed for $(sp.name)" _group=:control
    end
end

function _hardware_transfer_roll(sp::Spacecraft)
    ctrl = SCH.Control(sp.ves)
    try
        while true
            cmd = take!(sp.control.sink.rcs)
            @debug "Set roll to $cmd" _group=:input
            SCH.Roll!(ctrl, cmd)
            yield()
        end
    catch
        !isa(e, InvalidStateException) && @error "Unexpected loss of roll control for $(sp.name)" _group=:control
    finally
        @debug "Roll loop closed for $(sp.name)" _group=:control
    end
end

function _hardware_transfer_direction(sp::Spacecraft)
    ap = SCH.AutoPilot(sp.ves)
    try
        while true
            cmd = take!(sp.control.sink.direction)
            @trace "Set direction to $cmd" _group=:input
            cmd != (0f0, 0f0, 0f0) && SCH.TargetDirection!(ap, cmd)
            yield()
        end
    catch
        !isa(e, InvalidStateException) && @error "Unexpected loss of direction control for $(sp.name)" _group=:control
    finally
        @debug "Direction loop closed for $(sp.name)" _group=:control
    end
end

function _hardware_transfer_rcs(sp::Spacecraft)
    ctrl = SCH.Control(sp.ves)
    try
        while true
            fore, up, right = take!(sp.control.sink.rcs)
            @trace "Set RCS throttle to $fore, $up, $right" _group=:input
            !ismissing(fore)  && SCH.Forward!(ctrl, fore)
            !ismissing(up)    && SCH.Up!(ctrl, up)
            !ismissing(right) && SCH.Right!(ctrl, right)
            yield()
        end
    catch
        !isa(e, InvalidStateException) && @error "Unexpected loss of RCS control for $(sp.name)" _group=:control
    finally
        @debug "RCS loop closed for $(sp.name)" _group=:control
    end
end

"""
Close the spacecraft and active associated active loops.
Note that this does not close the spacecraft's time server, as it's by default
derived from the space center's clock.
"""
function Base.close(sp::Spacecraft)
    close(sp.control)
    close(sp.met)
end

function Base.close(mc::MasterControl)
    for con ∈ mc.users
        close(con)
    end
    close(mc.src)
    close(mc.sink)
end

function Base.close(con::SubControl)
    @info "Closing subcontrol $(con.name)" _group=:control
    close(con.engage)
    close(con.throttle)
    close(con.roll)
    close(con.direction)
    close(con.rcs)
end

function Base.close(con::ControlChannel)
    close(con.engage)
    close(con.throttle)
    close(con.roll)
    close(con.direction)
    close(con.rcs)
end

function Base.show(io::IO, sp::Spacecraft)
    name = nothing
    try
        name = SCH.Name(sp.ves)
    catch
        name = "Unknown spacecraft"
    end
    print(
        io,
        "$name ($(isopen(sp))) $(format_MET(sp.met.time))\n",
        "$(length(sp.parts)) registered parts: [$(join(keys(sp.parts), ','))]"
    )
end

function Base.show(io::IO, mc::MasterControl)
    status = Base.isopen(mc) ? "open" : "closed"
    active = mc.toggle[] ? "active" : "inactive"
    print(io, "Master Control ($status, $active) with $(length(mc.users)) users")
end

function Base.show(io::IO, con::SubControl)
    state = isopen(con) ? "open" : "closed"
    toggle = con.toggle[] ? "enabled" : "disabled"
    print(io, "SubControl $(con.name) ($state, $toggle)")
end

Base.isopen(sp::Spacecraft) = Base.isopen(sp.met.clients[1])
Base.isopen(mc::MasterControl) = Base.isopen(mc.sink)
Base.isopen(con::SubControl) = Base.isopen(con.engage)
Base.isopen(con::ControlChannel) = Base.isopen(con.engage)
