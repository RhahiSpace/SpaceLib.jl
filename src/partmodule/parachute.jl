module Chute

using SpaceLib
using ..PartModule

export AbstractParachute, RealChute, VanillaChute
export deploy!, cut!, arm!, disarm!, spares
export isarmed, iscut, isdeployed, isstowed

abstract type AbstractParachute <: Part end

@enum ParachuteState begin
    STOWED=0
    ARMED=2
    SEMI_DEPLOYED=4
    DEPLOYED=6
    CUT=8
end

struct RealChute <: AbstractParachute
    name::String
    part::SCR.Part
    chute::SCR.Parachute
    module_realchute::SCR.Module
end

struct VanillaChute <: AbstractParachute
    name::String
    part::SCR.Part
    chute::SCR.Parachute
    module_parachute::SCR.Module
end

function RealChute(part::SCR.Part)
    name = SCH.Title(part)
    @debug "Indexing $name" _group=:index
    chute = SCH.Parachute(part)
    module_realchute = getmodule(part, "RealChuteModule")
    RealChute(name, part, chute, module_realchute)
end

# exported functions

function arm!(chute::RealChute)
    if isstowed(chute)
        @info "Arming $(chute.name)" _group=:module
        _arm_action!(chute)
    else
        @debug "Ignored arm command for $(chute.name) (not stowed or already armed)" _group=:module
    end
end

function deploy!(chute::RealChute)
    if isstowed(chute)
        @info "Deploying $(chute.name)" _group=:module
        _deploy_action!(chute)
    else
        @debug "Ignored deploy command for $(chute.name) (not stowed)" _group=:module
    end
end

function cut!(chute::RealChute)
    if isdeployed(chute)
        @info "Cutting $(chute.name)" _group=:module
        _cut_action!(chute)
    else
        @debug "Ignored cut command for $(chute.name) (not deployed)" _group=:module
    end
end

function disarm!(chute::RealChute)
    if isarmed(chute)
        @info "Disarming $(chute.name)" _group=:module
        _disarm_action!(chute)
    else
        @debug "Ignored disarm command for $(chute.name) (not armed)" _group=:module
    end
end

function spares(chute::RealChute)
    value = SCH.GetFieldById(chute.module_realchute, "chuteCount")
    return parse(Int64, value)
end

isarmed(chute::RealChute) = SCH.State(chute.chute) == SC.EParachuteState_Armed
iscut(chute::RealChute) = SCH.State(chute.chute) == SC.EParachuteState_Cut
isdeployed(chute::RealChute) = SCH.State(chute.chute) == SC.EParachuteState_Deployed
isstowed(chute::RealChute) = SCH.State(chute.chute) == SC.EParachuteState_Stowed

# implementations

_deploy_native!(chute::VanillaChute) = SCH.Deploy(chute.chute)
_deploy_action!(chute::RealChute) = SCH.SetAction(chute.module_realchute, "Deploy chute", true)
function _deploy_event!(chute::RealChute)
    if SCH.HasEvent(chute.module_realchute, "Deploy Chute")
        @info "Deploying $(chute.name)" _group=:module
        SCH.TriggerEvent(chute.module_realchute, "Deploy Chute")
    else
        @warn "Deploy action for $(chute.name) unavailable" _group=:module
    end
end

_armed_native(chute::AbstractParachute) = SCH.Armed(chute.chute)
_armed_enum(chute::AbstractParachute) = SCH.State(chute.chute) == SC.EParachuteState_Armed

_arm_native!(chute::VanillaChute) = SCH.Arm(chute.chute)
_arm_action!(chute::RealChute) = SCH.SetAction(chute.module_realchute, "Arm parachute", true)
function _arm_event!(chute::RealChute)
    if SCH.HasEvent(chute.module_realchute, "Arm parachute")
        SCH.TriggerEvent(chute.module_realchute, "Arm parachute")
    else
        @warn "Arm action for $(chute.name) unavailable" _group=:module
    end
end

_disarm_action!(chute::RealChute) = SCH.SetAction(chute.module_realchute, "Disarm parachute", true)

_cut_native!(chute::VanillaChute) = SCH.Cut(chute.chute)
_cut_action!(chute::AbstractParachute) = SCH.SetAction(chute.module_realchute, "Cut chute", true)
function _cut_event!(chute::AbstractParachute)
    if SCH.HasEvent(chute.module_realchute, "Cut chute")
        SCH.TriggerEvent(chute.module_realchute, "Cut chute")
    else
        @warn "Cut action for $(chute.name) unavailable" _group=:module
    end
end

# shows

function _state(chute::RealChute)
    state = SCH.State(chute.chute)
    state == SC.EParachuteState_Armed ? "armed" :
    state == SC.EParachuteState_Cut ? "cut" :
    state == SC.EParachuteState_Deployed ? "deployed" :
    state == SC.EParachuteState_SemiDeployed ? "semi-deployed" :
    state == SC.EParachuteState_Stowed ? "stowed" : "unknown"
end

Base.show(chute::RealChute) = print(io, "RealChute($(chute.name), $(_state(chute)))")

end # module
