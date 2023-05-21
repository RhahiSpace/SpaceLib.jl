using Test
using SpaceLib
import KRPC.Interface.KRPC as KK
import KRPC.Interface.KRPC.RemoteTypes as KR
import KRPC.Interface.KRPC.Helpers as KH
import KRPC.Interface.SpaceCenter.Helpers as SCH

include("../setup_live.jl")

try
    scene = sc.conn |> KR.KRPC |> KH.CurrentGameScene
    scene != KK.EGameScene_Flight && error("This test should start while in flight scene")
    sp = add_active_vessel!(sc)
    con = subcontrol(sp)
    ctrl = SCH.Control(sp.ves)

    @testset "launchpad/throttle" begin
        put!(con.throttle, -1)
        delay(sc.ts)
        @test SCH.Throttle(ctrl) == 0

        put!(con.throttle, 0)
        delay(sc.ts)
        @test SCH.Throttle(ctrl) == 0

        put!(con.throttle, 0.5)
        delay(sc.ts)
        @test SCH.Throttle(ctrl) == 0.5

        put!(con.throttle, 1)
        delay(sc.ts)
        @test SCH.Throttle(ctrl) == 1

        put!(con.throttle, 2)
        delay(sc.ts)
        @test SCH.Throttle(ctrl) == 1
    end

    # should create a savefile for spacecraft in orbit, and test more controls.
finally
    close(sc)
end
