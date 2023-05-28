module Constants

using SpaceLib: SpaceCenter
export density

# physics

const g = 9.80665

# chemistry

const VANILLA_RESOURCES = (

)

const RO_RESOURCES = (
    "Aniline22",
    "IRFNA-III",
    "Nitrogen",
    "Helium",
    "ElectricCharge",
)

const DENSITY = Dict{String,Float32}(
    "Aniline22" => 1.23,
    "IRFNA-III" => 1.658,
    "Nitrogen" => 0.001251,
)

function populate_density!(table::Dict{String,Float32}, sc::SpaceCenter;
    resources=RO_RESOURCES,
    extras=nothing
)
    for name ∈ resources
        table[name] = SCH.Density(sc.conn, name)
    end
    if !isnothing(extras)
        for name ∈ extras
            if name ∉ resources
                d = SCH.Density(sc.conn, name)
                table[name] = d
                @warn "New substance found, consider adding density for $name => $d" _group=:system
            end
        end
    end
end

function density(name::String)
    value = get(DENSITY, name, nothing)
    isnothing(value) && error("$name is not a registered resource")
end

end # module
