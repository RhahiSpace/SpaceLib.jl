module PartModule

using SpaceLib

export Part
export getmodule, getmodules

abstract type Part end

"Look for a module with given name and index."
function getmodule(part::SCR.Part, name::String, idx::Integer=1)::SCR.Module
    modules = SCH.Modules(part)
    counter = 0
    for m ∈ modules
        if SCH.Name(m) == name
            counter += 1
            counter == idx && return m
        end
    end
    if counter > 0
        error("Module $name found, but index $idx does not exist.")
    else
        error("Module $name not found")
    end
end

"Look for all modules with given name."
function getmodules(part::SCR.Part, name::String, expected::Integer=0)
    modules = SCH.Modules(part)
    result = Vector{SCR.Module}()
    for m ∈ modules
        if SCH.Name(m) == name
            push!(result, m)
        end
    end
    if expected > 0 && length(modules) != expected
        error("Expected $expected $name modules, found $(length(modules))")
    end
    return result
end

# Note:
# For setting on/off for part actions, true/false value does not matter if
# the action does not care about states. It will just trigger.
# For wings, decreasing deflection angle will trigger regardless of true/false.
# For lights, true/false will change how the light is toggled into.

end # module
