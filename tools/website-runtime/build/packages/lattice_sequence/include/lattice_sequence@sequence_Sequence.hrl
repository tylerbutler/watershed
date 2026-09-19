-record(sequence, {
    replica_id :: lattice_core@replica_id:replica_id(),
    counter :: integer(),
    segments :: list(lattice_sequence@sequence:segment(any())),
    forwardings :: gleam@dict:dict(lattice_sequence@sequence:item_id(), lattice_sequence@sequence:forwarding()),
    frontier :: lattice_core@version_vector:version_vector()
}).
