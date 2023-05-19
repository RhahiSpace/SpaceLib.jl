
"""
The time resolution KSP has is about 0.02 seconds.
Half of that duraction is needed to match this time resolution.
"""
const TIME_RESOLUTION = Float64(0.019999999552965164 / 2)

"""
    Timeserver

A `Timeserver` maintains the universal or local clock and serves timestamps for
time based functions. This is done by managing a list of clients that are
subscribed to the time server, providing a caching layer to minimize streaming
overhad with KRPC.

# Fields

- `time`: The universal time in seconds.
- `clients`: The clients that are subscribed to the time server.
The first client is a controller.
- `type`: type of the clock. (UT, MET, and Offline)
"""
mutable struct Timeserver
    time::Float64
    clients::Vector{Channel{Float64}}
    type::String
    function Timeserver(stream::Union{Channel{Tuple{Float64}},KRPC.Listener}, type::String)
        signal = Channel{Float64}(1)
        clients = Vector{Channel{Float64}}()
        push!(clients, signal)
        ts = new(-1, clients, type)
        start_time_server!(ts, stream)
        # this should resolve immeidately after time server starts because
        # time should always be above 0 or higher, and server starts with -1.
        delay(ts, 0.1)
        ts
    end
end

# Timeserver constructors
"""
    Timeserver(conn::KRPC.KRPCConnection)

Start a timeserver using KRPC's universal time.

# Arguments

- `conn`: A KRPCConnection object.
"""
function Timeserver(conn::KRPC.KRPCConnection)
    stream = KRPC.add_stream(conn, (SC.get_UT(),))
    Timeserver(stream, "UT")
end

"""
    Timeserver(conn::KRPC.KRPCConnection, ves::SCR.Vessel)

Start timeserver using the Vessel's mission elapsed time."

# Arguments

- `conn`: A KRPCConnection object.
- `ves`: A Vessel object.
"""
function Timeserver(conn::KRPC.KRPCConnection, ves::SCR.Vessel)
    stream = KRPC.add_stream(conn, (SC.Vessel_get_MET(ves),))
    Timeserver(stream, "MET")
end

"""
    Timeserver()

Start a local time server for off-line testing.
"""
function Timeserver()
    clock = Channel{Tuple{Float64}}()
    @async begin
        try
            while true
                put!(clock, (time(),))
                sleep(0.005)
            end
        finally
            close(clock)
        end
    end
    Timeserver(clock, "Offline")
end

"""
    start_time_server!(ts::Timeserver, stream::Union{Channel{Tuple{Float64}}, KRPC.Listener})

Start a time server by fetching updated timestamps from the given stream and
publishing them to clients.
"""
function start_time_server!(ts::Timeserver, stream::Union{Channel{Tuple{Float64}}, KRPC.Listener})
    @async begin
        try
            running = true
            @debug "Starting time server" _group=:time
            while running
                ts.time, = next_value!(stream)
                index_offset = 0
                for (index, client) in enumerate(ts.clients)
                    if index == 1
                        isopen(client) && continue
                        # control channel has been closed. Shutdown timeserver.
                        @debug "Shutting down time server" _group=:time
                        running = false
                        break
                    end
                    try
                        !isready(client) && put!(client, ts.time)
                    catch e
                        # if a client is closed, we will get InvalidStateException.
                        # then remove the client from the list and proceed.
                        # otherwise, we have a different problem.
                        if !isa(e, InvalidStateException)
                            @error "Time server has crashed" _group=:time
                            error(e)
                        end
                        client = popat!(ts.clients, index - index_offset)
                        index_offset += 1
                        close(client)
                        @debug "Time channel closed." _group=:time
                    end
                end
            end
        finally
            # this block will run if clients list itself has been closed.
            for client in ts.clients
                close(client)
            end
            close(stream)
        end
    end
end

# subscription
"""
    subscribe(ts::Timeserver)

Subscribe to the time server. Close the returned channel to unsubscribe.
"""
function subscribe(ts::Timeserver)
    @debug "Time channel created"
    clock = Channel{Float64}(1)
    push!(ts.clients, clock)
    clock
end

"""
    subscribe(f::Function, ts::Timeserver)

Subscription that closes itself after `f` finishes.

```julia
subscribe(ts) do clock
    while true
        now = take!(clock)
        # do something
    end
end

subscribe(ts) do clock
    for now in clock
        # do something
        yield()
    end
end
```
"""
function subscribe(f::Function, ts::Timeserver)
    clock = subscribe(ts)
    try
        f(clock)
    finally
        close(clock)
    end
end

"""
    periodic_subscribe(ts::Timeserver, period::Real)

Subscription that updates time with given interval.
Useful for polling data periodically.
"""
function periodic_subscribe(ts::Timeserver, period::Real)
    coarse_clock = Channel{Float64}(1)
    fine_clock = subscribe(ts)
    last_update = 0.
    @async begin
        try
            for now in fine_clock
                if now - last_update > period
                    # skip sending if client hasn't received the time.
                    # this makes sure that every new time update is up to date
                    if !isready(coarse_clock)
                        put!(coarse_clock, now)
                        last_update = now
                    end
                end
            end
        finally
            close(fine_clock)
        end
    end
    coarse_clock
end

"""
    periodic_subscribe(f::Function, ts::Timeserver, period::Real)

Periodic subscription that closes itself after `f` finishes.
"""
function periodic_subscribe(f::Function, ts::Timeserver, period::Real)
    coarse_clock = periodic_subscribe(ts, period)
    try
        f(coarse_clock)
    finally
        close(coarse_clock)
    end
end

# delays
"""
    delay(ts::Timeserver, seconds::Real, name=nothing; parentid=ProgressLogging.ROOTID)

Wait for in-game seconds to pass.

# Arguments

  - `ts`: A Timeserver object.
  - `seconds`: The delay in seconds.
  - `name`: An optional name for the progress bar.
  - `parentid`: An optional parent ID for the progress bar.
"""
function delay(
    ts::Timeserver, seconds::Real, name::Union{Nothing, String}=nothing;
    parentid=ProgressLogging.ROOTID
)
    @debug "delay $seconds" _group=:time
    if seconds < 0.02
        @warn "Time delay is too short (should be 0.02 seconds or longer)" _group=:time
    end
    t₀ = ts.time
    t₁ = t₀
    progress = !isnothing(name)
    function _delay()
        try
            subscribe(ts) do clock
                for now in clock
                    t₁ = now
                    progress && @logprogress name min(1, (now - t₀) / seconds)
                    (now - t₀) ≥ (seconds - TIME_RESOLUTION) && break
                    yield()
                end
                @debug "delay $seconds complete" _group=:time
            end
        catch e
            if isa(e, InterruptException)
                @info "delay interrupted: $name" _group=:time
            else
                error(e)
            end
        end
    end
    if progress
        @withprogress name=name parentid=parentid _delay()
    else
        _delay()
    end
    return t₀, t₁
end

# other functions
"""
    Base.close(ts::Timeserver)

Close the time signalling channel, which results in stopping the update loop.
"""
Base.close(ts::Timeserver) = close(ts.clients[1])
next_value!(stream::KRPC.Listener) = KRPC.next_value(stream)
next_value!(channel::Channel) = take!(channel)
