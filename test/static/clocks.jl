using Test, SpaceLib
using SpaceLib: delay, periodic_subscribe

ts = Timeserver()

# test basic delay
t₀, t₁ = delay(ts, 1)
@test 0.9 ≤ (t₁ - t₀) ≤ 1.1

# test periodic delay
tchan = Channel{Float64}(10)
periodic_subscribe(ts, 0.2) do clock
    t0 = take!(clock)
    for _ = 1:6
        t = take!(clock)
        push!(tchan, t)
    end
end
take!(tchan)
@test -0.15 > take!(tchan) - take!(tchan) > -0.25
@test -0.15 > take!(tchan) - take!(tchan) > -0.25

close(ts)
