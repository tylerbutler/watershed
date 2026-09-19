-record(o_r_set, {
    replica_id :: lattice_core@replica_id:replica_id(),
    counter :: integer(),
    entries :: gleam@dict:dict(any(), gleam@set:set(lattice_sets@or_set:tag())),
    tombstones :: gleam@set:set(lattice_sets@or_set:tag()),
    pruned :: lattice_core@version_vector:version_vector()
}).
