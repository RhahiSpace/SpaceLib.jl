using SafeTestsets
using SpaceLib
using Logging
using Test

const GROUP = get(ENV, "GROUP", "static")
const KRPC_HOST = get(ENV, "KRPC_HOST", "127.0.0.1")
const KRPC_PORT = get(ENV, "KRPC_PORT", 50000)

global_logger(ConsoleLogger(Warn))

@time begin
    # static tests
    if GROUP == "static" || GROUP == "all"
        @time @safetestset "Clocks" begin include("static/clocks.jl") end
        @time @safetestset "Control pipe" begin include("static/controlpipe.jl") end
    end

    # live tests
    if GROUP == "all"
        @time @safetestset "Static clock tests" begin include("live/controlpipe.jl") end
    end
end
