-record(m_v_register, {
    replica_id :: lattice_core@replica_id:replica_id(),
    entries :: gleam@dict:dict(lattice_registers@mv_register:tag(), any()),
    vclock :: lattice_core@version_vector:version_vector()
}).
