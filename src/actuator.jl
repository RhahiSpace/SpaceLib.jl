"""
    stage!(sp::Spacecraft)::Vector{SCR.Vessel}

Stage the spacecraft and wait 0.5625 seconds to give KSP time between staging events.
"""
function stage!(sp::Spacecraft)
    @info "Stage commanded" _group=:stage
    ctrl = SCH.Control(sp.ves)
    acquire(sp, :stage)
    try
        vessels = SCH.ActivateNextStage(ctrl)
        if isa(vessels, Vector{SCR.Vessel}) && length(vessels) > 0
            @info "Stage separation confirmed" _group=:stage
        end
    finally
        @async begin
            delay(sp.ts, 0.5625)
            release(sp, :stage)
            @debug "Stage lock has been released" _group=:stage
        end
    end
end
