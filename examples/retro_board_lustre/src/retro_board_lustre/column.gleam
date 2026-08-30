//// The board's three fixed columns.
////
//// `id` values double as the schema channel keys (`document_schema.went_well`
//// etc.) and as the value of a note's `column` register — the render rule
//// matches the two by string equality, so this module is the single source of
//// truth for column identity.

pub type Column {
  WentWell
  ToImprove
  ActionItems
}

/// Wire id — equal to the sequence channel's key in the root map.
pub fn id(column: Column) -> String {
  case column {
    WentWell -> "went_well"
    ToImprove -> "to_improve"
    ActionItems -> "action_items"
  }
}

pub fn from_id(id: String) -> Result(Column, Nil) {
  case id {
    "went_well" -> Ok(WentWell)
    "to_improve" -> Ok(ToImprove)
    "action_items" -> Ok(ActionItems)
    _ -> Error(Nil)
  }
}

pub fn label(column: Column) -> String {
  case column {
    WentWell -> "Went well"
    ToImprove -> "To improve"
    ActionItems -> "Action items"
  }
}

/// Render / iteration order.
pub fn all() -> List(Column) {
  [WentWell, ToImprove, ActionItems]
}
