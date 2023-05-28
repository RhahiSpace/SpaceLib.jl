module Core

using SpaceLib
using ..PartModule
export ProbeCore, destruct!

struct ProbeCore <: Part
    name::String
    destruct::SCR.Module
    function ProbeCore(part::SCR.Part)
        name = SCH.Title(part)
        @debug "Indexing $name" _group=:index
        destruct = getmodule(part, "ModuleRangeSafety")
        new(name, destruct)
    end
end

"Blow up the spacecraft with this module. Optionally also shutdown the spacecraft"
function destruct!(part::ProbeCore, sp::Union{Spacecraft,Nothing}=nothing)
    @warn "Range safety has been triggered for $(part.name)" _group=:module
    SCH.SetAction(part.destruct, "Range Safety", true)
    !isnothing(sp) && close(sp)
end

end # module
