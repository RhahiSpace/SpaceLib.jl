function watchdog(sp::Spacecraft, core::Parts.ProbeCore)
    ref = ReferenceFrame.BCBF(sp)
    alt_prev = 0
    while true
        alt = SCH.Position(sp.ves, ref) |> norm
        alt_prev > 0 && alt_prev > alt && break
        alt_prev = alt
        delay(sp.ts, 2; log=false)
    end
    Parts.destruct!(core, sp)
    nothing
end

function stage_watchdog(
    sp::Spacecraft,
    engine::RealEngine,
    next::Union{Symbol,Nothing},
    interrupt::PersistentCondition
)
    @info "$(engine.name) watchdog activated."
    while !isset(interrupt)
        if thrust(engine) == 0
            !isnothing(next) && notify(sp, next)
            @warn "Watchdog detected engine failure" _group=:watchdog
            notify(interrupt; name="watchdog")
            return
        end
        delay(sp.ts, 0.09; log=false)
    end
end

function launch(sp::Spacecraft, e1::RealEngine, e2::RealEngine)
    (@async stage1(sp, e1)) |> errormonitor
    (@async stage2(sp, e1, e2)) |> errormonitor
    stage!(sp)
    delay(sp.ts, 0.55, "SRB")
    notify(sp, :stage1; name="launch")
end

function stage1(sp::Spacecraft, e1::RealEngine)
    wait(sp, :stage1)
    ignite!(sp, e1)
    delay(sp.ts, 0.2, "E1 ignition")
    stage!(sp)
    (@async stage_watchdog(sp, e1, :stage2, setevent(sp, :s1watch))) |> errormonitor
    delay(sp.ts, 47.5, "Stage 1"; interrupt=setevent(sp, :s1delay))
    notify(sp, :s1watch; name="stage1")
    notify(sp, :stage2; name="stage1")
end

function stage2(sp::Spacecraft, e1::RealEngine, e2::RealEngine)
    wait(sp, :stage2)
    notify(sp, :s1delay; name="stage2")
    ignite!(sp, e2)
    delay(sp.ts, 0.2, "E2 ignition")
    shutdown!(e1)
    stage!(sp)
    @async stage_watchdog(sp, e2, nothing, setevent(sp, :s2watch))
    delay(sp.ts, 47.5, "Stage 2"; interrupt=setevent(sp, :s2watch))
    notify(sp, :s2watch; name="stage2")
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
        delay(sp.ts, 0.1; log=false)
    end
    nothing
end
