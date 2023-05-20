abstract type AbstractControl end

@enum Command ENABLE DISABLE PRIO

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
        @debug "Creating control channel" _group=:rawcon
        new(create_control_channels(size)...)
    end
end

function Base.close(con::ControlChannel)
    close(con.engage)
    close(con.throttle)
    close(con.roll)
    close(con.direction)
    close(con.rcs)
end

function create_control_channels(size::Integer=1)
    e = Channel{Bool}(size)
    t = Channel{Float32}(size)
    r = Channel{Float32}(size)
    d = Channel{NTuple{3,Float64}}(size)
    rcs = Channel{NTuple{3,Union{Missing,Float32}}}(size)
    return (e,t, r, d, rcs)
end

"""
    SubControl(id, cmd, [size])

A wrapper around a control channel with the capability to be turned on and off.

# Fields
- `id`: Binary encoded identifier for the SubControl.
- `cmd`: Command channel to master to signal turn channels on or off.
- `cycle`: notified whenever master control loop finishes a cycle.
- `...`: identical to ControlChannel channels

# Extra arguments
- `size`: Buffer size for the channel. 1 is recommended.
- `num`: Channel number representation for control ID [0 - 30].
"""
struct SubControl <: AbstractControl
    id::UInt32
    cmd::Channel{UInt32}
    cycle::Condition

    engage::Channel{Bool}
    throttle::Channel{Float32}
    roll::Channel{Float32}
    direction::Channel{NTuple{3,Float64}}
    rcs::Channel{NTuple{3,Union{Missing,Float32}}}
    function SubControl(id::Unsigned, cmd::Channel{UInt32}, cycle::Condition, size::Integer)
        @info "Creating subcontrol" _group=:rawcon
        if id >= 0x40000000
            error("Invalid control channel")
        end
        new(id, cmd, cycle, create_control_channels(size)...)
    end
end

SubControl(num::Integer, cmd::Channel{UInt32}, cycle::Condition, size::Integer=1) = SubControl(convert(UInt32, 2^num), cmd, cycle, size)

function Base.close(ctrl::SubControl)
    @info "Closing subcontrol $(ctrl.id)" _group=:rawcon
    close(ctrl.engage)
    close(ctrl.throttle)
    close(ctrl.roll)
    close(ctrl.direction)
    close(ctrl.rcs)
end

function Base.show(io::IO, con::SubControl)
    if ispow2(con.id)
        name = "SubControl #$(round(Int, log2(con.id)))"
    else
        name = "Subcontrol 0b$(Base.bin(con.id, 30, false))"
    end
    isopen(con.cmd) ? print(io, "$name (open)") : print(io, "$name (closed)")
end

function disable(ctrl::SubControl)
    @debug "Control channel $(ctrl.id) disable requsted" _group=:rawcon
    push!(ctrl.cmd, ctrl.id)
end
function enable(ctrl::SubControl)
    @debug "Control channel $(ctrl.id) enable requsted" _group=:rawcon
    push!(ctrl.cmd, ctrl.id | 0x40000000)
end
function enable(f::Function, ctrl::SubControl)
    enable(ctrl)
    try
        wait(ctrl.cycle)
        f()
    finally
        disable(ctrl)
    end
end
function prioritze(ctrl::SubControl)
    @debug "Control channel $(ctrl.id) prioritze requsted" _group=:rawcon
    push!(ctrl.cmd, ctrl.id | 0x80000000)
end
function restore(ctrl::SubControl)
    @debug "Control channel $(ctrl.id) restore requsted" _group=:rawcon
    push!(ctrl.cmd, ctrl.id | 0xC0000000)
end
function prioritze(f::Function, ctrl::SubControl)
    prioritze(ctrl)
    try
        wait(ctrl.cycle)
        f()
    finally
        resetore(ctrl)
    end
end

"""
    MasterControl()

Manages a set of SubControls and connects to hardware ControlChannel.

# Fields
- `users`: A vector of SubControls.
- `cmd`: Receives commands for toggling specific channels.
- `chan`: Hardware ControlChannel
- `mask`: Binary mask for enabled/disabled states.
- `cycle`: Condition for notifying cycle completion of control loop.
- `active`: A stop switch for cutting off all SubControls, regardless of mask.
"""
mutable struct MasterControl
    users::Vector{SubControl}
    cmd::Channel{UInt32}
    chan::ControlChannel
    enable_mask::UInt32
    priority_mask::UInt32
    cycle::Condition
    active::Bool
    function MasterControl()
        users = Vector{AbstractControl}()
        cmd = Channel{UInt32}(1)
        chan = ControlChannel(1)
        cycle = Condition()
        mc = new(users, cmd, chan, 0x0, 0x0, cycle, true)
        (@async master_control_loop(mc)) |> errormonitor
        mc
    end
end

function Base.close(mc::MasterControl)
    for con ∈ mc.users
        close(con)
    end
    close(mc.chan)
end

"""
    master_control_loop(mc::MasterControl)

Start cycling through each subcontrol, handling data transfer and removal of
closed users. if the control is enabled and master control loop is in active
state.
"""
function master_control_loop(mc::MasterControl)
    @info "Master control loop started" _group=:rawcon
    try
        while isopen(mc.chan.engage)
            _mcl_command(mc)
            remove = nothing
            mask = mc.priority_mask & mc.enable_mask
            if mask == 0
                # no prioritized channel is enabled, fall back to enabled channels
                mask = mc.enable_mask
            end
            for (idx, u) ∈ enumerate(mc.users)
                # if engage channel is closed, the user is unsubscribed.
                if !isopen(u.engage)
                    remove = idx
                    continue
                end
                # mc.active is checked more frequenctly for faster response
                !mc.active && continue
                if u.id & mask > 0
                    _mcl_transfer(mc, u)
                else
                    _mcl_discard(u)
                end
            end
            # remove closed user (once per cycle)
            if !isnothing(remove)
                close(mc.users[remove])
                popat!(mc.users, remove)
            end
            # notify that a cycle of master control loop has been finished. this
            # is useful when the user does not want any data to be discarded, so
            # it can enable, wait until this signal and then start broadcasting.
            notify(mc.cycle)
            yield()
        end
    finally
        @info "Master control loop closed" _group=:rawcon
    end
end

function _mcl_command(mc::MasterControl)
    !isready(mc.cmd) && return
    cmd = take!(mc.cmd)
    @info "command" cmd
    cmd & 0xC0000000 == 0xC0000000 && return (mc.priority_mask |= cmd)
    cmd & 0x80000000 > 0 && return (mc.priority_mask &= ~cmd)
    cmd & 0x40000000 > 0 && return (mc.enable_mask |= cmd)
    return (mc.enable_mask &= ~cmd)
end

function _mcl_transfer(mc::MasterControl, u::SubControl)
    # transfer incoming data into immediate controller
    isready(u.engage)    && put!(mc.chan.engage,    take!(u.engage))
    isready(u.throttle)  && put!(mc.chan.throttle,  take!(u.throttle))
    isready(u.roll)      && put!(mc.chan.roll,      take!(u.roll))
    isready(u.direction) && put!(mc.chan.direction, take!(u.direction))
    isready(u.rcs)       && put!(mc.chan.rcs,       take!(u.rcs))
end

function _mcl_discard(u::SubControl)
    # when control is locked or mask is inactive, discard all values.
    isready(u.engage)    && take!(u.engage)
    isready(u.throttle)  && take!(u.throttle)
    isready(u.roll)      && take!(u.roll)
    isready(u.direction) && take!(u.direction)
    isready(u.rcs)       && take!(u.rcs)
end

function Base.show(io::IO, mc::MasterControl)
    status = isopen(mc.chan.engage) ? "open" : "closed"
    active = mc.active ? "active" : "inactive"
    print(
        io,
        "Master Control ($status, $active) with $(length(mc.users)) users\n",
        "- Enabled:     0b$(Base.bin(mc.enable_mask, 32, false)) = $(mc.enable_mask)\n",
        "- Prioritized: 0b$(Base.bin(mc.priority_mask, 32, false)) = $(mc.priority_mask)\n",
    )
end


"""
    subcontrol(m::MasterControl, num::Int, size::Integer=1)

Create a new subcontrol unit, register it to the master control loop. The
SubControl is initialized as enabled.
"""
function subcontrol(m::MasterControl, num::Int, size::Integer=1)
    con = SubControl(num, m.cmd, size)
    push!(m.users, con)
    return con
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
- `mc`: Master control channel of the spacecraft.
- `ts`: UT timeserver to access global time.
- `met`: MET timeserver to access vehicle's specific mission elapsed time.
Useful for resuming mission from save, as MET is not volatile.
"""
struct Spacecraft
    name::String
    ves::SCR.Vessel
    parts::Dict{Symbol,SCR.Part}
    events::Dict{Symbol,Condition}
    sync::Dict{Symbol,Base.Semaphore}
    mc::MasterControl
    ts::Timeserver
    met::Timeserver
end

function Spacecraft(
    conn::KRPC.KRPCConnection,
    ves::SCR.Vessel;
    name = nothing,
    parts = Dict{Symbol,SCR.Part}(),
    events = Dict{Symbol,Condition}(),
    mc = MasterControl(),
    ts = Timeserver(),
    met = Timeserver(conn, ves)
)
    name = isnothing(name) ? SCH.Name(ves) : name
    ts.type == "Offline" && @warn "Using offline time server; vessel timing maybe out of sync." _group=:system
    sync = Dict{Symbol,Base.Semaphore}(:stage => Base.Semaphore(1))
    @async begin
        try
            # if time server closes or gets stop signal,
            # the spacecraft will no longer be controllable.
            wait(ts.clients[1])
        finally
            # close the control channels.
            @info "Spacecraft $name has been shut down." _group=:system
            close(mc)
        end
    end
    sp = Spacecraft(name, ves, parts, events, sync, mc, ts, met)
    (@async hardware_control_loop(sp, mc)) |> errormonitor
    return sp
end

function Base.close(sp::Spacecraft)
    close(sp.mc)
    close(sp.ts)
    close(sp.met)
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
        "$name ($(sp.ts.time)) $(format_MET(sp.met.time))\n",
        "$(length(sp.parts)) parts: [$(join(keys(sp.parts), ','))]"
    )
end

"""
    hardware_control_loop(sp::Spacecraft, m::MasterControl)

Control loop that delivers control input into hardware.
"""
function hardware_control_loop(sp::Spacecraft, m::MasterControl)
    ctrl = SCH.Control(sp.ves)
    ap = SCH.AutoPilot(sp.ves)

    function _direction(cmd::NTuple{3,Float64})
        # if norm(cmd) == 0 && return
        cmd == (0f0, 0f0, 0f0) && return
        SCH.TargetDirection!(ap, cmd)
    end

    function _rcs(cmd::NTuple{3,Union{Missing,Float32}})
        fore, up, right = cmd
        !ismissing(fore) && SCH.Forward!(ctrl, fore)
        !ismissing(up) && SCH.Up!(ctrl, up)
        !ismissing(right) && SCH.Right!(ctrl, right)
    end

    while isopen(m.chan.engage)
        isready(m.chan.engage) && take!(u.chan.engage) ? SCH.Engage(ap) : SCH.Disengage(sp)
        isready(m.chan.throttle) && take!(u.chan.throttle) |> SCH.Throttle!
        isready(m.chan.roll) && take!(u.chan.roll) |> SCH.Roll!
        isready(m.chan.direction) && take!(u.chan.direction) |> _direction
        isready(m.chan.rcs) && take!(u.chan.rcs) |> _rcs
        yield()
    end
end

"""
    acquire(sp, sym)

Release a semaphore of the Spacecraft identified by `sym`.
"""
function release(sp::Spacecraft, sym::Symbol)
    sym ∉ keys(sp.sync) && return
    Base.release(sp.sync[sym])
end

"""
    acquire(sp, sym, [limit])

Acquire or create a semaphore of the Spacecraft identified by `sym`.
"""
function acquire(sp::Spacecraft, sym::Symbol, limit::Integer=1)
    if sym ∉ keys(sp.sync)
        sp.sync[sym] = Base.Semaphore(limit)
    end
    Base.acquire(sp.sync[sym])
end

"""
    acquire(f, sp, sym, [limit])

Acquire or create a semaphore of the Spacecraft identified by `sym`,
execute function `f` and then release the semaphore.
"""
function acquire(f::Function, sp::Spacecraft, sym::Symbol, limit::Integer=1)
    try
        acquire(sp, sym, limit)
        f()
    finally
        release(sp, sym)
    end
end
