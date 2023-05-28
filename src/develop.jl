module Develop

using SpaceLib
using KRPC
import KRPC.Interface.SpaceCenter.Helpers as SCH
import KRPC.Interface.SpaceCenter.RemoteTypes as SCR
import KRPC.Interface.Drawing as D
import KRPC.Interface.Drawing.RemoteTypes as DR
import KRPC.Interface.Drawing.Helpers as DH

const MODULE_FIELD_BLACKLIST = ("TestFlightFailure_IgnitionFail",)

function list_parts(sp::Spacecraft)
    parts = SCH.Parts(sp.ves) |> SCH.All
    for (idx, p) ∈ enumerate(parts)
        tag = SCH.Tag(p)
        tag = tag == "" ? "" : " #$tag"
        println("[$idx] $(SCH.Name(p))", tag)
    end
    return parts
end

"Part actions that can be assigned to action groups in editor"
function list_actions(part::SCR.Part)
    modules = SCH.Modules(part)
    println("--- actions ---")
    for m ∈ modules
        actions = SCH.Actions(m)
        println("Module[$(length(actions))]: ", SCH.Name(m))
        for a ∈ actions
            println("  -> ", a)
        end
    end
end

"Buttons that can be clicked in game"
function list_events(part::SCR.Part)
    modules = SCH.Modules(part)
    println("--- events ---")
    for m ∈ modules
        events = SCH.Events(m)
        println("Module[$(length(events))]: ", SCH.Name(m))
        for e ∈ events
            println("  -> ", e)
        end
    end
end

function list_fields(part::SCR.Part)
    modules = SCH.Modules(part)
    println("--- fields ---")
    for m ∈ modules
        name = SCH.Name(m)
        if name ∈ MODULE_FIELD_BLACKLIST
            println("  -> Skipped module fields")
            continue
        end
        fields = SCH.Fields(m)
        println("Module[$(length(fields))]: ", name)
        for f ∈ fields
            println("  -> ", f)
        end
    end
end

function list_modules(part::SCR.Part)
    modules = SCH.Modules(part)
    for (idx, m) ∈ enumerate(modules)
        println("[$idx] $(SCH.Name(m))")
    end
end

function list_info(part::SCR.Part)
    println(SCH.Title(part))
    println("")
    list_actions(part)
    println("")
    list_events(part)
    println("")
    list_fields(part)
end

get_field(m::SCR.Module, key::String) = get(SCH.Fields(m), key, nothing)

end #module
