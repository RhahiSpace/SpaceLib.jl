module Decoupler

using SpaceLib
using ..PartModule

abstract type AbstractDecoupler <: Part end
export AbstractDecoupler, RegularDecoupler
export decouple!, crossfeed!

struct RegularDecoupler <: AbstractDecoupler
    name::String
    part::SCR.Part
    decoupler::SCR.Decoupler
    module_top::SCR.Module
    module_bottom::SCR.Module
    module_crossfeed::SCR.Module
end

function RegularDecoupler(part::SCR.Part)
    name = SCH.Title(part)
    @debug "Indexing $name" _group=:index
    decoupler = SCH.Decoupler(part)
    (top, bottom) = getmodules(part, "ModuleDecouple")
    crossfeed = getmodule(part, "ModuleToggleCrossfeed")
    RegularDecoupler(name, part, decoupler, top, bottom, crossfeed)
end

function decouple!(dec::RegularDecoupler; top::Bool=false, bottom::Bool=false)
    target = top ? (bottom ? "both sides" : "top side") : (bottom ? "bottom side" : "")
    target != "" && @info "Decoupling $(dec.name) $target" _group=:module
    top && SCH.SetAction(dec.module_top, "Decouple", true)
    bottom && SCH.SetAction(dec.module_bottom, "Decouple", true)
end

function crossfeed!(dec::RegularDecoupler, enable::Bool)
    if enable
        SCH.SetAction(dec.module_crossfeed, "Enable Crossfeed", true)
    else
        SCH.SetAction(dec.module_crossfeed, "Disable Crossfeed", true)
    end
end

function Base.show(io::IO, dec::RegularDecoupler)
    print(io, "RegularDecoupler [$(dec.name)]")
end

end # module
