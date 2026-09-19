-record(g_counter, {
    dict :: gleam@dict:dict(lattice_core@replica_id:replica_id(), integer()),
    self_id :: lattice_core@replica_id:replica_id()
}).
