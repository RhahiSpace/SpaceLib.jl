using SafeTestsets
using SpaceLib
using Test

const GROUP = get(ENV, "GROUP", "all")
const KRPC_HOST = get(ENV, "KROC_HOST", "127.0.0.1")
const KRPC_PORT = get(ENV, "KRPC_PORT", 50000)

@time begin
    if GROUP == "all"
    end

    if GROUP == "static" || GROUP == "all"
        @time @safetestset "Static clock tests" begin include("static/clocks.jl") end
    end
end
