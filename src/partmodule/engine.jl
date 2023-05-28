module Engine

using ErrorTypes
using ProgressLogging
using SpaceLib
using SpaceLib: @optionalprogress
using UUIDs
using ..PartModule
using ..Constants: g, density
import KRPC.Interface.SpaceCenter.Helpers as SCH
import KRPC.Interface.SpaceCenter.RemoteTypes as SCR

export AbstractEngine, RealEngine, VanillaEngine
export isstable, runtime, MTBF, spooltime
export ignite!, shutdown!, thrust, wait_for_burnout

abstract type AbstractEngine end
abstract type SingleEngine <: AbstractEngine end
abstract type RealSingleEngine <: SingleEngine end

struct VanillaEngine <: SingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    massflow::Float64
end

function VanillaEngine(part::SCR.Part)
    name = SCH.Title(part)
    ṁ = mass_flow_rate(engine)
    @debug "Indexing $name" _group=:index
    VanillaEngine(name, part, SCH.Engine(part), ṁ)
end

struct RealEngine <: RealSingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    module_realfuel::SCR.Module
    module_testflight::SCR.Module
    spooltime::Float64
    massflow::Float64
end

struct RealSolidEngine <: RealSingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    module_realfuel::SCR.Module
    module_testflight::SCR.Module
    spooltime::Float64
    massflow::Float64
end

function RealEngine(part::SCR.Part)
    name = SCH.Title(part)
    @debug "Indexing $name" _group=:index
    engine = SCH.Engine(part)
    rfm = getmodule(part, "ModuleEnginesRF")
    tfm = getmodule(part, "TestFlightReliability_EngineCycle")
    spool = spooltime(rfm)
    ṁ = mass_flow_rate(engine)
    ṁ ≤ 0 && error("Invalid massflow for $name")
    return RealEngine(name, part, engine, rfm, tfm, spool, ṁ)
end

struct ClusterEngine{T<:SingleEngine}
    engines::Vector{T}
end

function Base.show(io::IO, e::VanillaEngine)
    print(io, "VanillaEngine ($(e.name))")
end

function Base.show(io::IO, e::RealEngine)
    print(io, "RealEngine ($(e.name))")
end

function Base.show(io::IO, e::ClusterEngine)
    num = length(e.engines)
    print(io, "ClusterEngine ($num engines)")
end

function isstable(e::RealEngine)
    value = SCH.GetFieldById(e.module_realfuel, "propellantStatus")
    i₁ = findfirst('(', value)
    i₂ = findfirst(')', value)
    return parse(Float64, value[i₁+1:i₂-3])
end
isstable(e::VanillaEngine) = 100.0

function runtime(e::RealEngine)
    value = SCH.GetFieldById(e.module_testflight, "engineOperatingTime")
    return parse(Float64, value)
end
runtime(e::VanillaEngine) = 0.0

# this function will be changed in the future to display full time in seconds.
MTBF(e::RealEngine) = SCH.GetFieldById(e.module_testflight, "currentMTBF")
MTBF(e::VanillaEngine) = "Inf"

function spooltime(m::SCR.Module)
    value = SCH.GetFieldById(m, "effectiveSpoolUpTime")
    return parse(Float64, value)
end
spooltime(e::VanillaEngine) = 0.0

function ignite!(e::SingleEngine)
    @info "Ignition commanded for $(e.name)" _group=:motor
    SCH.Active!(e.engine, true)
end

function shutdown!(e::SingleEngine)
    @info "Shutdown commanded for $(e.name)" _group=:motor
    SCH.Active!(e.engine, false)
end

function ignite!(sp::Spacecraft, e::SingleEngine; error=false, expected_thrust=0)
    ignite!(e)
    delay(sp.ts, e.spooltime)
    th = thrust(e)
    if th > 0 && th ≥ expected_thrust
        @info "Ignition confirmed for $(e.name)" _group=:motor
    else
        @warn "Ignition failed for $(e.name)" _group=:motor
        error && error()
    end
    return th
end

thrust(e::SingleEngine) = SCH.Thrust(e.engine)

"""
Expected burn time of the engine, in seconds.
Devates from MJ value. 0.12 seconds to compute.
"""
function remaining_burn_time(sp::Spacecraft, e::SingleEngine; massflow::Real = e.massflow)
    ṁ = massflow
    mₚ = effective_propellant_mass(sp, e.engine)
    return t = mₚ / ṁ
end

"""
Mass flow rate of engine.
Deviates from MJ value.
"""
function mass_flow_rate(engine::SCR.Engine)
    thv = SCH.MaxVacuumThrust(engine)
    isp = SCH.VacuumSpecificImpulse(engine)
    return ṁ = thv / isp / g
end

"""Available fuel mass, in kg. Computed from engine. 0.020 seconds to compute."""
function effective_propellant_mass(sp::Spacecraft, engine::SCR.Engine)
    propellants = SCH.Propellants(engine)
    rmin = minimum(SCH.TotalResourceAvailable(p) / SCH.Ratio(p) for p in propellants)
    return mₚ = sum(rmin * SCH.Ratio(p) * density(SCH.Name(p)) for p in propellants)
end

end

end # module
