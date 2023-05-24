module PartModule

import KRPC.Interface.SpaceCenter.RemoteTypes as SCR
import KRPC.Interface.SpaceCenter.Helpers as SCH

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

end # module
