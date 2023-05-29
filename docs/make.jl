using SpaceLib
using Documenter

DocMeta.setdocmeta!(SpaceLib, :DocTestSetup, :(using SpaceLib); recursive = true)

makedocs(;
    modules = [SpaceLib],
    authors = "Rhahi <git@rhahi.com>",
    repo = "https://github.com/RhahiSpace/SpaceLib.jl/blob/{commit}{path}#{line}",
    sitename = "SpaceLib.jl",
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://docs.rhahi.space/SpaceLib.jl",
        edit_link = "main",
        assets = String[],
    ),
    pages = ["Home" => "index.md"],
)

deploydocs(; repo = "github.com/RhahiSpace/SpaceLib.jl", devbranch = "main")
