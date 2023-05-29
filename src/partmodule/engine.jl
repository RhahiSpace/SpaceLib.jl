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

struct StoredPropellant
    name::String
    ratio::Float32
    density::Float32
    capacity::Float64
    loss::Float64
    propellant::SCR.Propellant
end

struct EnginePropellant
    resources::Vector{StoredPropellant}
    massflow::Float32
    residual_ratio::Float32
    function EnginePropellant(engine::SCR.Engine, residual_ratio::Real)
        @info "Indexing engine propellant" _group=:index
        krpc_propellants = SCH.Propellants(engine)
        resources = Vector{StoredPropellant}()
        massflow = static_mass_flow_rate(engine)
        for kp ∈ krpc_propellants
            name = SCH.Name(kp)
            ratio = SCH.Ratio(kp)
            capacity = SCH.TotalResourceCapacity(kp)
            loss = capacity * residual_ratio
            p = StoredPropellant(name, ratio, density(name), capacity, loss, kp)
            push!(resources, p)
        end
        new(resources, massflow, residual_ratio)
    end
end

amount(p::StoredPropellant) = max(0,SCH.TotalResourceAvailable(p.propellant)-p.loss)

"""Available fuel mass, in kg. Not completely accurate."""
function effective_propellant_mass(ep::EnginePropellant)
    length(ep.resources) == 0 && return 0.0
    times = Vector{Float64}()
    masses = Vector{Float64}()
    for p ∈ ep.resources
        effective_amount = amount(p)
        push!(times, effective_amount/p.ratio)
        push!(masses, effective_amount*p.density)
    end
    tmin = minimum(times)
    sum = 0
    for (i, m) ∈ enumerate(masses)
        sum += tmin / times[i] * m
    end
    isnan(sum) && return 0.0
    return sum
end

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
    propellant::EnginePropellant
end

struct RealSolidEngine <: RealSingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    module_realfuel::SCR.Module
    module_testflight::SCR.Module
    spooltime::Float32
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
    prop = EnginePropellant(engine, residual(rfm))
    return RealEngine(name, part, engine, rfm, tfm, spool, prop)
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
    massflow::Real = e.propellant.massflow,
)
    ṁ = massflow
    mₚ = effective_propellant_mass(e.propellant)
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

@enum BurnoutReason INTERRUPT BURNOUT MARGIN TIMEOUT ENGINEOFF

function wait_for_burnout(sp::Spacecraft, e::SingleEngine;
    margin::Real=0,
    timeout::Real=0,
    period::Real=0.5,
    progress::Bool=false,
    name::String=first(e.name, 10),
    parentid::Base.UUID=ProgressLogging.ROOTID,
    interrupt::Union{EventCondition,Nothing}=nothing,
    allow_engine_shutoff=true,
)
    t₀ = sp.ts.time
    τ₀ = remaining_burn_time(e)
    τ_prev = τ₀
    e_prev = SCH.Active(e.engine)
    pid1 = uuid4()
    pid2 = uuid4()
    if τ₀ == 0
        @warn "Trying to wait for engine with no remaining burn time $(e.name)" _group=:motor
    end
    periodic_subscribe(sp.ts, period) do clock
        try
            for now = clock
                if isset(interrupt)
                    @info "Interrupted burnout wait of $(e.name)" _group=:motor burntime=now-t₀
                    return INTERRUPT
                end
                τ = remaining_burn_time(e)
                if τ != τ₀ && τ == τ_prev
                    @info "Burnout detected (no massflow) for $(e.name)" _group=:motor burntime=now-t₀
                    return BURNOUT
                end
                if !allow_engine_shutoff
                    engine_status = SCH.Active(e.engine)
                    if e_prev && !engine_status
                        @info "Burnout detected (engine off) for $(e.name)" _group=:motor burntime=now-t₀
                        return BURNOUT
                    end
                    e_prev = engine_status
                end
                if progress
                    fraction = min(1, (τ₀-τ) / τ₀)
                    @info ProgressLogging.Progress(pid1, fraction; parentid=parentid, name=name, done=false) _group=:ProgressLogging
                end
                if margin > 0 && τ ≤ margin
                    @info "Burnout margin has been reached for $(e.name)" _group=:motor burntime=now-t₀ margin
                    return MARGIN
                end
                if timeout > 0
                    if progress
                        fraction = min(1, (now - t₀) / timeout)
                        @info ProgressLogging.Progress(pid2, fraction; parentid=pid1, name="↱timeout", done=false) _group=:ProgressLogging
                    end
                    if (now - t₀) ≥ timeout
                        @info "Burnout timeout has been reached for $(e.name)" _group=:motor burntime=now-t₀
                        return TIMEOUT
                    end
                end
                τ_prev = τ
                yield()
            end
        finally
            progress && @info ProgressLogging.Progress(pid1; done=true) _group=:ProgressLogging
            progress && timeout > 0 && @info ProgressLogging.Progress(pid2; done=true) _group=:ProgressLogging
        end
    end
end

end # module
