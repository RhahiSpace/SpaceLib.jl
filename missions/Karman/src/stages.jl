function watchdog(sp::Spacecraft, core::Parts.ProbeCore)
    ref = ReferenceFrame.BCBF(sp)
    alt_prev = 0
    while true
        alt = SCH.Position(sp.ves, ref) |> norm
        alt_prev > 0 && alt_prev > alt && break
        alt_prev = alt
        delay(sp.ts, 2)
    end
    Parts.destruct!(core, sp)
    nothing
end

function launch(sp::Spacecraft, e1::RealEngine, e2::RealEngine)
    stage!(sp)
    delay(sp.ts, 0.7, "SRB")
    ignite!(e1)
    delay(sp.ts, 0.3, "E1 ignition")
    stage!(sp)
    delay(sp.ts, 47.5, "Stage 1")
    ignite!(e2)
    delay(sp.ts, 0.3, "E2 ignition")
    shutdown!(e1)
    stage!(sp)
    delay(sp.ts, 47.5, "Stage 2")
end

function science(sp::Spacecraft)
    bcbf = ReferenceFrame.BCBF(sp.ves)
    h₀ = SCH.Position(sp.ves, bcbf) |> norm
    flight = SCH.Flight(sp.ves, bcbf)
    while isopen(sp)
        drag = SCH.Drag(flight) |> norm
        mass = SCH.Mass(sp.ves)
        alt = SCH.Position(sp.ves, bcbf) |> norm
        vel = SCH.Velocity(sp.ves, bcbf) |> norm
        th = SCH.Thrust(sp.ves)
        @info "" altitude=(alt-h₀) velocity=vel thrust=th mass=mass drag=drag _group=:atmospheric
        delay(sp.ts, 0.1)
    end
    nothing
end
