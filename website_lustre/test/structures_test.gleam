import gleam/list
import gleeunit/should
import watershed_site/structures

pub fn field_atlas_catalog_matches_the_astro_families_test() {
  structures.all()
  |> list.map(fn(family) {
    #(
      family.slug,
      family.name,
      family.tagline,
      list.map(family.entries, fn(entry) { #(entry.name, entry.kind) }),
    )
  })
  |> should.equal([
    #("counters", "Counters", "Numbers that many hands move at once.", [
      #("SharedCounter", structures.Dds),
      #("GCounter", structures.Crdt),
      #("PnCounter", structures.Crdt),
    ]),
    #(
      "sets",
      "Sets",
      "Lists of things, as people add and remove at the same time.",
      [
        #("GSet", structures.Crdt),
        #("TwoPSet", structures.Crdt),
        #("OrSet", structures.Crdt),
      ],
    ),
    #(
      "registers",
      "Registers",
      "One shared value, and three different answers to a race.",
      [
        #("LWWRegister", structures.Crdt),
        #("MvRegister", structures.Crdt),
        #("RegisterCollection", structures.Dds),
      ],
    ),
    #(
      "maps",
      "Maps",
      "Keyed state that picks a winner, keeps an edit, or grows into a tree.",
      [
        #("SharedMap", structures.Dds),
        #("LWWMap", structures.Crdt),
        #("OrMap", structures.Crdt),
        #("SharedDirectory", structures.Dds),
      ],
    ),
    #(
      "sequences",
      "Sequences",
      "Ordered lists that stay ordered while everyone rearranges them.",
      [
        #("SharedSequence", structures.Crdt),
        #("SharedText", structures.Crdt),
      ],
    ),
    #(
      "coordination",
      "Coordination",
      "Deciding who owns what, and agreeing before acting.",
      [
        #("Claims", structures.Dds),
        #("OrderedCollection", structures.Dds),
        #("TaskManager", structures.Dds),
        #("PactMap", structures.Dds),
      ],
    ),
    #(
      "transforms",
      "Transforms",
      "One shared document, kept in agreement as everyone edits.",
      [
        #("JsonOt", structures.Ot),
        #("SharedRichText", structures.Ot),
      ],
    ),
  ])
}

pub fn field_atlas_description_lists_every_family_test() {
  structures.description()
  |> should.equal(
    "Field guide to watershed's collaborative data structures, grouped into families: counters, sets, registers, maps, sequences, coordination, transforms. How each converges, and what it is best for.",
  )
}
