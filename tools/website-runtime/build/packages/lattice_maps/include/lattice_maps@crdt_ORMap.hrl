-record(o_r_map, {
    replica :: lattice_core@replica_id:replica_id(),
    spec :: lattice_maps@crdt:crdt_spec(any()),
    state :: lattice_maps@internal@or_map_engine:state(lattice_maps@crdt:crdt(any()))
}).
