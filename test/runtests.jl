using SafeTestsets
using SpaceLib
using Logging
using Test

const GROUP = get(ENV, "GROUP", "static")

global_logger(ConsoleLogger(Warn))

@time begin
    # static tests
    if GROUP == "all" ||  GROUP == "static"
        @time @safetestset "clocks" begin include("static/clocks.jl") end
        @time @safetestset "control pipe" begin include("static/controlpipe.jl") end
        @time @safetestset "synchronizations" begin include("static/events.jl") end
    end

    # live tests
    if GROUP == "all" || GROUP == "live"
        @time @safetestset "live/control pipe" begin include("live/controlpipe.jl") end
    end
end
