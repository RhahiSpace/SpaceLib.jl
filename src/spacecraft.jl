abstract type Toggle end
mutable struct MutableToggle active::Bool end
struct StaticToggle active::Bool end

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
    toggle::Toggle

    engage::Channel{Bool}
    throttle::Channel{Float32}
    roll::Channel{Float32}
    direction::Channel{NTuple{3,Float64}}
    rcs::Channel{NTuple{3,Union{Missing,Float32}}}
    function SubControl(
        name::String,
        sink::ControlChannel,
        toggle::Toggle=MutableToggle(true),
        size::Integer=1
    )
        @info "Creating subcontrol $name" _group=:rawcon
        con = new(name, sink, toggle, create_control_channels(size)...)
        @async _transfer(con.engage, sink.engage, toggle, "$name/engage")
        @async _transfer(con.throttle, sink.throttle, toggle, "$name/throttle")
        @async _transfer(con.roll, sink.roll, toggle, "$name/roll")
        @async _transfer(con.direction, sink.direction, toggle, "$name/direction")
        @async _transfer(con.rcs, sink.rcs, toggle, "$name/rcs")
        return
    end
end

function Base.close(con::SubControl)
    @info "Closing subcontrol $(con.name)" _group=:rawcon
    close(con.engage)
    close(con.throttle)
    close(con.roll)
    close(con.direction)
    close(con.rcs)
end

function Base.show(io::IO, con::SubControl)
    state = isopen(con) ? "open" : "closed"
    toggle = con.toggle.active ? "enabled" : "disabled"
    print(io, "SubControl $(con.name) ($state, $toggle)")
end

disable(con::SubControl) = con.toggle.switch = false
enable(con::SubControl) = push!(con.cmd, con.id | 0x40000000)
function enable(f::Function, con::SubControl)
    enable(con)
    try
        f()
    finally
        disable(con)
    end
end

"""
    MasterControl()

Manages a set of SubControls and connects to hardware ControlChannel.

# Command bits
- Bit 0-29: Channel bit
- Bit 30-31: command bit
    - 00: Disable    (0x00000000)
    - 01: Enable     (0x40000000)
    - 10: Restore    (0x80000000)
    - 11: Prioritize (0xC0000000)

# Mask bits
- Bit 0-29: Channel enabled bit
- Bit 30-31: Unused (garbage bit)

# Fields
- `users`: A vector of SubControls.
- `cmd`: Receives commands for toggling specific channels.
- `chan`: Hardware ControlChannel
- `enable_mask`: Binary mask for enabled/disabled channels.
- `proirity_mask`: Binary mask for prioritized channels. Respects disable bit.
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
    close(mc.cmd)
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
        while isopen(mc.chan)
            _mcl_command(mc)
            remove = nothing
            mask = mc.priority_mask & mc.enable_mask
            if mask == 0
                # no prioritized channel is enabled, fall back to enabled channels
                mask = mc.enable_mask
            end
            for (idx, u) ∈ enumerate(mc.users)
                # if engage channel is closed, the user is unsubscribed.
                if !isopen(u)
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
    status = Base.isopen(mc) ? "open" : "closed"
    active = mc.active ? "active" : "inactive"
    print(
        io,
        "Master Control ($status, $active) with $(length(mc.users)) users\n",
        "- Enabled:     0b$(Base.bin(mc.enable_mask, 32, false)) = $(mc.enable_mask)\n",
        "- Prioritized: 0b$(Base.bin(mc.priority_mask, 32, false)) = $(mc.priority_mask)\n",
    )
end

Base.isopen(mc::MasterControl) = Base.isopen(mc.cmd)
Base.isopen(ctrl::SubControl) = Base.isopen(ctrl.engage)
Base.isopen(ctrl::ControlChannel) = Base.isopen(ctrl.engage)

"""
    subcontrol(m::MasterControl, num::Int, size::Integer=1)

Create a new subcontrol unit, register it to the master control loop. The
SubControl is initialized as enabled.
"""
function subcontrol(m::MasterControl, num::Integer, size::Integer=1)
    con = SubControl(num, m.cmd, m.cycle, size)
    push!(m.users, con)
    enable(con)
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
            wait(met.clients[1])
        finally
            # close the control channels.
            @info "Spacecraft $name has been shut down." _group=:system
            close(mc)
            close(met)
        end
    end
    sp = Spacecraft(name, ves, parts, events, sync, mc, ts, met)
    (@async hardware_control_loop(sp, mc)) |> errormonitor
    return sp
end

"""
Close the spacecraft and active associated active loops.
Note that this does not close the spacecraft's time server, as it's by default
derived from the space center's clock.
"""
function Base.close(sp::Spacecraft)
    close(sp.mc)
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
        "$name ($(isopen(sp))) $(format_MET(sp.met.time))\n",
        "$(length(sp.parts)) registered parts: [$(join(keys(sp.parts), ','))]"
    )
end

Base.isopen(sp::Spacecraft) = Base.isopen(sp.met.clients[1])

"""
    hardware_control_loop(sp::Spacecraft, m::MasterControl)

Control loop that delivers control input into hardware.
"""
function hardware_control_loop(sp::Spacecraft, m::MasterControl)
    ctrl = SCH.Control(sp.ves)
    ap = SCH.AutoPilot(sp.ves)

    function _engage(cmd::Bool)
        cmd ? SCH.Engage(ap) : SCH.Disengage(ap)
    end

    function _throttle(cmd::Float32)
        SCH.Throttle!(ctrl, clamp(cmd, 0f0, 1f0))
    end

    function _direction(cmd::NTuple{3,Float64})
        # if norm(cmd) == 0 && return
        cmd == (0f0, 0f0, 0f0) && return
        SCH.TargetDirection!(ap, cmd)
    end

    function _rcs(cmd::NTuple{3,Union{Missing,Float32}})
        fore, up, right = cmd
        !ismissing(fore)  && SCH.Forward!(ctrl, fore)
        !ismissing(up)    && SCH.Up!(ctrl, up)
        !ismissing(right) && SCH.Right!(ctrl, right)
    end

    @info "Hardware control loop started" _group=:rawcon
    try
        while isopen(m.chan)
            isready(m.chan.engage)    && take!(m.chan.engage)    |> _engage
            isready(m.chan.throttle)  && take!(m.chan.throttle)  |> _throttle
            isready(m.chan.roll)      && take!(m.chan.roll)      |> SCH.Roll!
            isready(m.chan.direction) && take!(m.chan.direction) |> _direction
            isready(m.chan.rcs)       && take!(m.chan.rcs)       |> _rcs
            yield()
        end
    finally
        @info "Hardware control loop ended" _group=:rawcon
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
