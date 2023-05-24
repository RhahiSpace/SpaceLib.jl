module Engine

using ErrorTypes
using SpaceLib
using ..PartModule: getmodule
import KRPC.Interface.SpaceCenter.Helpers as SCH
import KRPC.Interface.SpaceCenter.RemoteTypes as SCR

export AbstractEngine, RealEngine, VanillaEngine
export isstable, runtime, MTBF, spooltime
export ignite!, shutdown!

abstract type AbstractEngine end
abstract type SingleEngine <: AbstractEngine end

struct VanillaEngine <: SingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
end

function VanillaEngine(part::SCR.Part)
    name = SCH.Title(part)
    @debug "Indexing $name" _group=:index
    VanillaEngine(name, part, SCH.Engine(part))
end

struct RealEngine <: SingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    rfmodule::SCR.Module
    tfmodule::SCR.Module
    spooltime::Float64
end

struct RealSolidEngine <: SingleEngine
    name::String
    part::SCR.Part
    engine::SCR.Engine
    rfmodule::SCR.Module
    tfmodule::SCR.Module
    spooltime::Float64
end

function RealEngine(part::SCR.Part)
    name = SCH.Title(part)
    @debug "Indexing $name" _group=:index
    engine = SCH.Engine(part)
    rfm = getmodule(part, "ModuleEnginesRF")
    tfm = getmodule(part, "TestFlightReliability_EngineCycle")
    spool = spooltime(rfm)
    return RealEngine(name, part, engine, rfm, tfm, spool)
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
    value = SCH.GetFieldById(e.rfmodule, "propellantStatus")
    i₁ = findfirst(status, '(')
    i₂ = findfirst(status, ')')
    return parse(Float64, value[i₁+1:i₂-3])
end
isstable(e::VanillaEngine) = 100.0

function runtime(e::RealEngine)
    value = SCH.GetFieldById(e.tfmodule, "engineOperatingTime")
    return parse(Float64, value)
end
runtime(e::VanillaEngine) = 0.0

# this function will be changed in the future to display full time in seconds.
MTBF(e::RealEngine) = SCH.GetFieldById(e.rfmodule, "currentMTBF")
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

end # module
