using KerbalMath
using KerbalRemoteLogging
using KRPC
using SpaceLib
using .Engine
import KRPC.Interface.SpaceCenter as SC
import KRPC.Interface.SpaceCenter.RemoteTypes as SCR
import KRPC.Interface.SpaceCenter.Helpers as SCH

function timestring(sp::Spacecraft)
    return () -> begin
        try
            sp.met.time > 0 && return sp.met.time |> SpaceLib.format_MET
            return sp.ts.time |> SpaceLib.format_UT
        catch
            return ""
        end
    end
end

include("setup.jl")
include("stages.jl")

function setup_logger(sp::Spacecraft)
    logger = KerbalRemoteLogger(;
        port=50003,
        timestring=timestring(sp),
        console_loglevel=Base.LogLevel(-1000),
        console_exclude_group=(:ProgressLogging,:time,),
        disk_directory="/home/rhahi/.julia/dev/SpaceLib/missions/Karman/log",
        data_directory="/home/rhahi/.julia/dev/SpaceLib/missions/Karman/data",
        data_groups=(:atmospheric,),
    )
    Base.global_logger(logger)
end

function main()
    sc = SpaceCenter("Karman 1", "10.0.0.51")
    sp = add_active_vessel!(sc)
    setup_logger(sp)
    con = subcontrol(sp, "main")
    core, e1, e2 = setup(sp, con)
    (@async science(sp)) |> errormonitor
    (@async launch(sp, e1, e2)) |> errormonitor
    wait(@async watchdog(sp, core))
end

main()
