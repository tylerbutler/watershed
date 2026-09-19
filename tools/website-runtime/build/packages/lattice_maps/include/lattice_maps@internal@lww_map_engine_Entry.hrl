-record(entry, {
    value :: gleam@option:option(any()),
    timestamp :: integer(),
    provenance :: lattice_maps@internal@lww_map_engine:provenance()
}).
