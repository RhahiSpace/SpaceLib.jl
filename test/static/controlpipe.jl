using Test
using SpaceLib

mc = MasterControl()
con1 = subcontrol(mc, "test1")
con2 = subcontrol(mc, "test2")

function _test_exact(from::Channel{T}, to::Channel{T}, value) where {T}
    @test isopen(from)
    @test !isready(from)
    put!(from, value)
    sleep(0.01)
    @test isready(to)
    @test take!(to) == value
end

function _test_approx(from::Channel{T}, to::Channel{T}, value; atol=0.01) where {T}
    @test isopen(from)
    @test !isready(from)
    put!(from, value)
    sleep(0.01)
    @test isready(to)
    @test isapprox(take!(to), value; atol=atol)
end

function _test_approx_tuple(from::Channel{T}, to::Channel{T}, value; atol=0.01) where {T<:Tuple}
    @test isopen(from)
    @test !isready(from)
    put!(from, value)
    sleep(0.01)
    @test isready(to)
    for (i, x) = enumerate(take!(to))
        if ismissing(x)
            @test ismissing(value[i])
            continue
        end
        @test isapprox(x, value[i]; atol=atol)
    end
end

function _test_disabled(from::Channel{T}, to::Channel{T}, value) where {T}
    @test isopen(from)
    @test !isready(from)
    put!(from, value)
    sleep(0.01)
    @test !isready(to)
    @test !isready(from)
end

@testset "control lifecycle" begin
    @test length(mc.users) == 2
    con3 = subcontrol(mc, "test3")
    @test length(mc.users) == 3
    close(con3)
    @test !isopen(con3)
    @test !isopen(con3.engage)
    @test !isopen(con3.throttle)
    @test !isopen(con3.roll)
    @test !isopen(con3.direction)
    @test !isopen(con3.rcs)
    SpaceLib._gc(mc, 0)
    @test length(mc.users) == 2
end

@testset "control transfer, engage" failfast=true begin
    _test_exact(con1.engage, mc.sink.engage, true)
    _test_exact(con2.engage, mc.sink.engage, true)
    _test_exact(con1.engage, mc.sink.engage, false)
    _test_exact(con2.engage, mc.sink.engage, false)
end

@testset "control transfer, throttle" failfast=true begin
    _test_approx(con1.throttle, mc.sink.throttle, 0.5)
    _test_approx(con2.throttle, mc.sink.throttle, 0.5)
    _test_approx(con1.throttle, mc.sink.throttle, 0)
    _test_approx(con2.throttle, mc.sink.throttle, 0)
    _test_approx(con1.throttle, mc.sink.throttle, 1)
    _test_approx(con2.throttle, mc.sink.throttle, 1)
    _test_approx(con1.throttle, mc.sink.throttle, 0.)
    _test_approx(con2.throttle, mc.sink.throttle, 0.)
end

@testset "control transfer, roll" failfast=true begin
    _test_approx(con1.roll, mc.sink.roll, 500)
    _test_approx(con2.roll, mc.sink.roll, 500)
    _test_approx(con1.roll, mc.sink.roll, -100.0)
    _test_approx(con2.roll, mc.sink.roll, -100.0)
    _test_approx(con1.roll, mc.sink.roll, 1)
    _test_approx(con2.roll, mc.sink.roll, 1)
    _test_approx(con1.roll, mc.sink.roll, 0.)
    _test_approx(con2.roll, mc.sink.roll, 0.)
end

@testset "control transfer, direction" failfast=true begin
    _test_approx_tuple(con1.direction, mc.sink.direction, (0.1, 100, 300))
    _test_approx_tuple(con2.direction, mc.sink.direction, (0.1, 100, 300))
    _test_approx_tuple(con1.direction, mc.sink.direction, (-0.1, 100, -30.0))
    _test_approx_tuple(con2.direction, mc.sink.direction, (-0.1, 100, -30.0))
end

@testset "control transfer, rcs" failfast=true begin
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (0.1, 100, 300))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (0.1, 100, 300))
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (-0.1f0, 100f0, -30.0))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (-0.1f0, 100f0, -30.0))
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (-0.1f0, 10f0, -30.0f0))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (-0.1f0, 10f0, -30.0f0))
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (missing, 10f0, -30.0f0))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (missing, 10f0, -30.0f0))
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (missing, missing, missing))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (missing, missing, missing))
end

@testset "control toggle, rcs" failfast=true begin
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (0.1, 100, 300))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (0.1, 100, 300))
    disable(con1)
    _test_disabled(con1.rcs, mc.sink.rcs, (-0.1f0, 100f0, -30.0))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (-0.1f0, 100f0, -30.0))
    enable(con1)
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (-0.1f0, 10f0, -30.0f0))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (-0.1f0, 10f0, -30.0f0))
    disable(con1)
    disable(con2)
    _test_disabled(con1.rcs, mc.sink.rcs, (missing, 10f0, -30.0f0))
    _test_disabled(con2.rcs, mc.sink.rcs, (missing, 10f0, -30.0f0))
    enable(con1) do
        _test_approx_tuple(con1.rcs, mc.sink.rcs, (missing, 10f0, -30.0f0))
    end
    enable(con2) do
        _test_approx_tuple(con2.rcs, mc.sink.rcs, (missing, 10f0, -30.0f0))
    end
    @test !con1.toggle[]
    @test !con2.toggle[]
    enable(con1)
    enable(con2)
    @test con1.toggle[]
    @test con2.toggle[]
end

@testset "control toggle, master" failfast=true begin
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (0.1, 100, 300))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (0.1, 100, 300))
    disable(mc)
    _test_disabled(con1.rcs, mc.sink.rcs, (-0.1f0, 100f0, -30.0))
    _test_disabled(con2.rcs, mc.sink.rcs, (-0.1f0, 100f0, -30.0))
    enable(mc)
    _test_approx_tuple(con1.rcs, mc.sink.rcs, (-0.1f0, 10f0, -30.0f0))
    _test_approx_tuple(con2.rcs, mc.sink.rcs, (-0.1f0, 10f0, -30.0f0))
end
