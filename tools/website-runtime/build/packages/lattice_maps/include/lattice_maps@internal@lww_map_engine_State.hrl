-record(state, {
    entries :: gleam@dict:dict(binary(), lattice_maps@internal@lww_map_engine:entry(any())),
    pruned_timestamp :: integer()
}).
