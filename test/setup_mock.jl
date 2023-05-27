using KRPC
using Sockets
using SpaceLib
using UUIDs

const conn = KRPC.KRPCConnection(
    TCPSocket(),
    TCPSocket(),
    Array{UInt8,1}(),
    Channel{Bool}(1),
)

const ves = SCR.Vessel(conn, 0)

const sp = Spacecraft(conn, ves;
    name = "MockCraft",
    control = MasterControl(10),
    met = Timeserver(),
)
