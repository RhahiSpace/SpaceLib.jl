using Test
include("../setup_mock.jl")

@testset "PersistentCondition" begin
    # detached event
    e0 = EventCondition()
    @test !isset(e0)
    notify(e0)
    @test isset(e0)

    # event creation with event!
    @test length(sp.events) == 1
    e1 = event!(sp, :e1)
    @test length(sp.events) == 2
    @test !isset(e1)
    @test value(e1) |> isnothing
    notify(sp, :e1)  # trigger with nothing
    @test isset(e1)
    @test value(e1) |> isnothing

    # event creation with notify
    notify(sp, :e2, "value")
    e2 = sp.events[:e2]
    @test length(sp.events) == 3
    @test isset(e2)
    @test value(e2) == "value"
    # event resetting
    reset(e2)
    @test !isset(e2)
    @test value(e2) |> isnothing

    # event creation with wait
    task = @async wait(sp, :e3)
    while !istaskstarted(task) sleep(0.01) end
    @test length(sp.events) == 4
    notify(sp, :e3, "value")
    @test fetch(task) == "value"

    # event retrieval and setting
    _e2 = event(sp, :e2)
    @test e2 === _e2
    event!(sp, _e2; active=true)
    _e2 = sp.events[:e2]
    @test isset(_e2)
    @test value(_e2) |> isnothing
end
