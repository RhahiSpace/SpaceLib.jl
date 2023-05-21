"Workaround for enum doubling in KRPC. Does not work the other way around."
function ==(krpc::KRPC.kRPCTypes.Enum, code::KRPC.kRPCTypes.Enum)
    return krpc.value == code.value*2
end
