-record(forwarding_map, {
    entries :: gleam@dict:dict(lattice_sequence@sequence:item_id(), lattice_sequence@sequence:forwarding())
}).
