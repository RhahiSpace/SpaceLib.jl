function preload(sp)
    delay(sp.ts, 0.1)
    delay(sp.ts, 1)
    delay(sp.ts, 0.1, "Preload 1")
    delay(sp.ts, 1, "Preload 2")
end

function register_parts(sp::Spacecraft)
    parts = SCH.Parts(sp.ves)
    core = SCH.WithTitle(parts, "Aerobee Sounding Rocket Telemetry Unit")[1] |> Parts.ProbeCore
    e1 = SCH.WithTag(parts, "e1")[1] |> Engine.RealEngine
    e2 = SCH.WithTag(parts, "e2")[1] |> Engine.RealEngine
    return (core, e1, e2)
end

function setup(sp::Spacecraft, con::SubControl)
    put!(con.throttle, 1)
    preload(sp)
    ctrl = SCH.Control(sp.ves)
    if SCH.Throttle(ctrl) ≉ 1
        @error "Throttle check failed"
        error("Throttle check failed")
    end
    return register_parts(sp)
end
