-record(state, {
    clock :: integer(),
    entries :: gleam@dict:dict(binary(), lattice_maps@internal@or_map_engine:entry(any()))
}).
