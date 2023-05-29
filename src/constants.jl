module Constants

using SpaceLib: SpaceCenter
export density

# physics

const g = 9.80665

# chemistry

const VANILLA_DENSITY = Dict{String,Float32}()

const RO_DENSITY = Dict{String,Float32}(
    "AK20" => 1.499,
    "AK27" => 1.494,
    "Ammonia" => 0.000769,
    "Aniline" => 1.02,
    "Aniline22" => 1.042,
    "Aniline37" => 1.0585,
    "ElectricCharge" => 0.0,
    "Helium" => 0.0001786,
    "HTP" => 1.431,
    "Hydrazine" => 1.004,
    "Hydrogen" => 8.99e-5,
    "IRFNA-III" => 1.658,
    "Kerosene" => 0.82,
    "LqdAmmonia" => 0.7021,
    "LqdOxygen" => 1.1409999,
    "Nitrogen" => 0.001251,
    "SoundingPayload" => 0.5,
    "Water" => 1.0,
)

function populate_density!(sc::SpaceCenter;
    table::Dict{String,Float32}=RO_DENSITY,
    extras=nothing
)
    for name ∈ table
        new = SCH.Density(sc.conn, name)
        old = table[name]
        if new ≉ old
            @warn "Detected changed value for $name ($old -> $new)"
            table[name] = new
        end
    end
    if !isnothing(extras)
        for name ∈ extras
            if name ∉ table
                value = SCH.Density(sc.conn, name)
                table[name] = value
                entry = "\"$name\" => $value"
                @warn "New resource found, consider adding to density table" entry _group=:system
            end
        end
    end
end

"kg per in-game unit"
function density(name::String; table=RO_DENSITY)
    density = get(table, name, nothing)
    isnothing(density) && error("$name is not a registered resource")
    return density
end

end # module
