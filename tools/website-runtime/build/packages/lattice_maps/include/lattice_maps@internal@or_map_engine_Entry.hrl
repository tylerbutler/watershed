-record(entry, {
    generation :: lattice_maps@internal@or_map_engine:generation(),
    membership :: lattice_sets@or_set:o_r_set(binary()),
    value :: gleam@option:option(any())
}).
