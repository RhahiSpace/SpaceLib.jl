macro optionalprogress(name, parentid, block)
    return quote
        if isnothing($name)
            $block
        else
            @withprogress name=name parentid=parentid begin
                $block
            end
        end
    end |> esc
end
