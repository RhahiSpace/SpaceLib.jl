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
    massflow::Float32
end

function VanillaEngine(part::SCR.Part)
    name = SCH.Title(part)
    ṁ = static_mass_flow_rate(engine)
    @debug "Indexing $name" _group=:index
    VanillaEngine(name, part, SCH.Engine(part), ṁ)
end

struct RealEngine <: RealSingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    module_realfuel::SCR.Module
    module_testflight::SCR.Module
    spooltime::Float32
    massflow::Float32
    residual::Float64
end

struct RealSolidEngine <: RealSingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    module_realfuel::SCR.Module
    module_testflight::SCR.Module
    spooltime::Float32
    massflow::Float32
end

function RealEngine(part::SCR.Part)
    name = SCH.Title(part)
    @debug "Indexing $name" _group=:index
    engine = SCH.Engine(part)
    rfm = getmodule(part, "ModuleEnginesRF")
    tfm = getmodule(part, "TestFlightReliability_EngineCycle")
    spool = spooltime(rfm)
    ṁ = static_mass_flow_rate(engine)
    ṁ ≤ 0 && error("Invalid massflow for $name")
    r = residual(rfm)
    return RealEngine(name, part, engine, rfm, tfm, spool, ṁ, r)
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
    return parse(Float32, value[i₁+1:i₂-3])
end
isstable(e::VanillaEngine) = 100.0f0

function runtime(e::RealEngine)
    value = SCH.GetFieldById(e.module_testflight, "engineOperatingTime")
    return parse(Float32, value)
end
runtime(e::VanillaEngine) = 0.0f0

function residual(m::SCR.Module)
    value = SCH.GetFieldById(m, "predictedMaximumResidualsGUI")
    return parse(Float64,value)
end

function ignitions(e::SingleEngine)
    value = SCH.GetFieldById(e.module_realfuel, "ignitions")
    return parse(Int64,value)
end

# this function will be changed in the future to display full time in seconds.
# example: 9.88m
MTBF(e::RealEngine) = SCH.GetFieldById(e.module_testflight, "currentMTBF")
MTBF(e::VanillaEngine) = "Inf"

function spooltime(m::SCR.Module)
    value = SCH.GetFieldById(m, "effectiveSpoolUpTime")
    return parse(Float32, value)
end
spooltime(e::VanillaEngine) = 0.0f0

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

function remaining_burn_time(e::SingleEngine;
    massflow::Real = e.massflow,
)
    ṁ = massflow
    mₚ = effective_propellant_mass(e)
    return t = mₚ / ṁ
end

function static_mass_flow_rate(engine::SCR.Engine)
    thv = SCH.MaxVacuumThrust(engine)
    isp = SCH.VacuumSpecificImpulse(engine)
    return ṁ = thv / isp / g
end

function realtime_mass_flow_rate(e::SingleEngine)
    value = SCH.GetFieldById(e.module_realfuel, "massFlowGui")
    return parse(Float32, value)
end

"""Available fuel mass, in kg. Not completely accurate."""
function effective_propellant_mass(e::SingleEngine; residual=e.residual)
    if !SCH.Active(e.engine) && ignitions(e) == 0
        # if engine is off and has no ignitions left, it cannot use any fuel.
        return 0
    end
    propellants = SCH.Propellants(e.engine)
    length(propellants) == 0 && return 0
    times = Vector{Float64}()
    masses = Vector{Float64}()
    for p in propellants
        loss = SCH.TotalResourceCapacity(p)*residual
        amount = SCH.TotalResourceAvailable(p)
        eff_amount = max(0,amount-loss)
        push!(times, eff_amount / SCH.Ratio(p))
        push!(masses, eff_amount*density(SCH.Name(p)))
    end
    tmin = minimum(times)
    sum = 0
    for (i, m) ∈ enumerate(masses)
        sum += tmin / times[i] * m
    end
    return sum
end

end

end # module
