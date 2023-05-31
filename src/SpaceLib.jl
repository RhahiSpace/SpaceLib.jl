module SpaceLib

using ErrorTypes
using KRPC
using ProgressLogging
using MacroTools
using Logging
import KRPC.Interface.SpaceCenter as SC
import KRPC.Interface.SpaceCenter.RemoteTypes as SCR
import KRPC.Interface.SpaceCenter.Helpers as SCH
import KRPC.Interface.KRPC as KK
import KRPC.Interface.KRPC.RemoteTypes as KR
import KRPC.Interface.KRPC.Helpers as KH
import Base: close, show, isopen, ==, notify, acquire, release, wait, reset

# modules
export Develop, ReferenceFrame, Constants
export SC, SCR, SCH, KK, KR, KH

# workarounds.jl
export ==

# stage.jl
export action!, stage!

# time.jl
export Timeserver
export connect, periodic_subscribe, delay

# spacecraft.jl & synchronization.jl
export Spacecraft, EventCondition
export AbstractControl, MasterControl, ControlChannel, SubControl
export subcontrol, isset, reset, event!, event, create_event, notify, wait, value, timestring

# spacecenter.jl
export SpaceCenter
export add_active_vessel!, remove_active_vessel!, remove_vessel!
export subscribe, disable, enable

# parts and modules
export PartModule, Decoupler, Engine, Parachute, CommandModule

# common functions
export acquire, release, @trace

include("macros.jl")
include("workarounds.jl")

# system
include("time.jl")
include("spacecraft.jl")
include("events.jl")
include("delay.jl")
include("spacecenter.jl")

# constants
include("constants.jl")
include("frame.jl")

# actuators
include("stage.jl")
include("partmodule/partmodule.jl")
include("partmodule/resources.jl")
include("partmodule/engine.jl")
include("partmodule/command.jl")
include("partmodule/decoupler.jl")
include("partmodule/parachute.jl")

# others
include("develop.jl")

end # module
