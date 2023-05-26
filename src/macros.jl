macro optionalprogress(name, parentid, block)
    return quote
        if isnothing($name) || $name == false
            $block
        else
            @withprogress name=name parentid=parentid begin
                $block
            end
        end
    end |> esc
end

macro trace(exs...)
    :($Base.@logmsg $Base.CoreLogging.LogLevel(-2000) $(exs...))
end
