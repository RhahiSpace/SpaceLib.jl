"""
    delay(ts::Timeserver, seconds::Real, name=nothing; parentid=ProgressLogging.ROOTID)

Wait for in-game seconds to pass.

# Arguments

  - `ts`: A Timeserver object.
  - `seconds`: The delay in seconds.
  - `name`: An optional name for the progress bar.
  - `parentid`: An optional parent ID for the progress bar.
"""
function delay(
    ts::Timeserver,
    seconds::Real=TIME_RESOLUTION*2,
    name::Union{Nothing,String}=nothing;
    parentid::Base.UUID=ProgressLogging.ROOTID,
    interrupt::Union{EventCondition,Nothing}=nothing,
    log::Bool=true
)
    log && @trace "delay $seconds" _group=:time
    if seconds < TIME_RESOLUTION*2
        @warn "Time delay is too short (should be 0.02 seconds or longer)" _group=:user
    end
    t₀ = ts.time
    t₁ = t₀
    @optionalprogress name parentid begin
        try
            subscribe(ts) do clock
                for now in clock
                    if isset(interrupt)
                        @info "delay interrupted: $name" _group=:time
                        break
                    end
                    t₁ = now
                    !isnothing(name) && @logprogress name min(1, (now - t₀) / seconds)
                    (now - t₀) ≥ (seconds - TIME_RESOLUTION) && break
                    yield()
                end
                log && @debug "delay $seconds complete" _group=:time
            end
        catch e
            if isa(e, InterruptException)
                @info "delay interrupted: $name" _group=:user
            else
                error(e)
            end
        end
    end
    return t₀, t₁
end
