host = get(ENV, "KRPC_HOST", "127.0.0.1")
port = get(ENV, "KRPC_PORT", 50000)
sc = SpaceCenter("$(PROGRAM_FILE |> basename)" |> basename, host, port)
