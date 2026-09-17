import gleam/list
import gleam/string

pub type Kind {
  Dds
  Crdt
  Ot
}

pub type Entry {
  Entry(name: String, kind: Kind)
}

pub type Family {
  Family(slug: String, name: String, tagline: String, entries: List(Entry))
}

pub fn all() -> List(Family) {
  [
    Family("counters", "Counters", "Numbers that many hands move at once.", [
      Entry("SharedCounter", Dds),
      Entry("GCounter", Crdt),
      Entry("PnCounter", Crdt),
    ]),
    Family(
      "sets",
      "Sets",
      "Lists of things, as people add and remove at the same time.",
      [Entry("GSet", Crdt), Entry("TwoPSet", Crdt), Entry("OrSet", Crdt)],
    ),
    Family(
      "registers",
      "Registers",
      "One shared value, and three different answers to a race.",
      [
        Entry("LWWRegister", Crdt),
        Entry("MvRegister", Crdt),
        Entry("RegisterCollection", Dds),
      ],
    ),
    Family(
      "maps",
      "Maps",
      "Keyed state that picks a winner, keeps an edit, or grows into a tree.",
      [
        Entry("SharedMap", Dds),
        Entry("LWWMap", Crdt),
        Entry("OrMap", Crdt),
        Entry("SharedDirectory", Dds),
      ],
    ),
    Family(
      "sequences",
      "Sequences",
      "Ordered lists that stay ordered while everyone rearranges them.",
      [Entry("SharedSequence", Crdt), Entry("SharedText", Crdt)],
    ),
    Family(
      "coordination",
      "Coordination",
      "Deciding who owns what, and agreeing before acting.",
      [
        Entry("Claims", Dds),
        Entry("OrderedCollection", Dds),
        Entry("TaskManager", Dds),
        Entry("PactMap", Dds),
      ],
    ),
    Family(
      "transforms",
      "Transforms",
      "One shared document, kept in agreement as everyone edits.",
      [Entry("JsonOt", Ot), Entry("SharedRichText", Ot)],
    ),
  ]
}

pub fn description() -> String {
  let names =
    all()
    |> list.map(fn(family) { string.lowercase(family.name) })
    |> string.join(", ")
  "Field guide to watershed's collaborative data structures, grouped into families: "
  <> names
  <> ". How each converges, and what it is best for."
}

pub fn kind_name(kind: Kind) -> String {
  case kind {
    Dds -> "DDS"
    Crdt -> "CRDT"
    Ot -> "OT"
  }
}
