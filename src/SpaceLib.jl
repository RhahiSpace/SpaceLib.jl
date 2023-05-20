module SpaceLib

using ErrorTypes
using KRPC
using ProgressLogging
using MacroTools
import KRPC.Interface.SpaceCenter as SC
import KRPC.Interface.SpaceCenter.RemoteTypes as SCR
import KRPC.Interface.SpaceCenter.Helpers as SCH
import Base: close, show, isopen

# modules
export Actuator, PartModule, Develop

# time.jl
export Timeserver
export connect, periodic_subscribe, delay

# spacecraft.jl
export Spacecraft, AbstractControl, MasterControl, ControlChannel
export subcontrol

# spacecenter.jl
export SpaceCenter
export connect, add_active_vessel!, remove_active_vessel!
export subscribe

# common functions
export acquire, release

include("macros.jl")
include("time.jl")
include("spacecraft.jl")
include("spacecenter.jl")
# include("PartModule/PartModule.jl")
# include("actuator.jl")
include("frame.jl")
include("develop.jl")

end # module
