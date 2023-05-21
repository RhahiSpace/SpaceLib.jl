# A base for KRPC connection and spacecenter managements.

"""
    SpaceCenter()

Represents connection to KRPC. Should persist while the game is running.

# Note

Commands can have problem executing after reverting a launch. To solve
connection issues, restart KRPC server (press Stop and Start).

# Fields
- `conn`: a KRPC.KRPCConnection object.
- `center`: KRPC's SpaceCenter object.
- `time`: a time server that will provide updated in-game universal time.
- `crafts`: a list of Spacecrafts to be controlled.
"""
struct SpaceCenter
    conn::KRPC.KRPCConnection
    center::SCR.SpaceCenter
    ts::Timeserver
    crafts::Array{Spacecraft,1}
end

function SpaceCenter(
    name::String="Julia",
    host::String="127.0.0.1",
    port::Integer=50000
)
    conn = kerbal_connect(name, host, port, port+1)
    crafts = Array{Spacecraft,1}()
    SpaceCenter(conn, SCR.SpaceCenter(conn), Timeserver(conn), crafts)
end

function Base.show(io::IO, sc::SpaceCenter)
    status = isopen(sc.conn.conn) ? "open" : "closed"
    print(io, "SpaceCenter ($status) $(format_UT(sc.ts.time))")
    for sp in sc.crafts
        print(io, "\n  - $sp")
    end
end

function Base.close(sc::SpaceCenter)
    for c ∈ sc.crafts
        close(c)
    end
    close(sc.ts)
    close(sc.conn.conn)
end

function add_active_vessel!(sc::SpaceCenter; name=nothing)
    ves = SCH.ActiveVessel(sc.center)
    sp = Spacecraft(sc.conn, ves; name=name, ts=sc.ts)
    push!(sc.crafts, sp)
    return sp
end

function _remove_vessel!(sc::SpaceCenter, inds::Vector{T}) where T <: Integer
    for i = inds
        close(sc.crafts[i])
    end
    deleteat!(sc.crafts, inds)
    return length(inds)
end

function remove_vessel!(sc::SpaceCenter, sp::Spacecraft)
    sps = findall(x -> x === sp, sc.crafts)
    _remove_vessel!(sc, sps)
end

function remove_vessel!(sc::SpaceCenter, ves::SCR.Vessel)
    sps = findall(x -> x.ves === ves, sc.crafts)
    _remove_vessel!(sc, sps)
end

function remove_active_vessel!(sc::SpaceCenter)
    ves = SCH.ActiveVessel(sc.center)
    remove_vessel!(sc, ves)
end
