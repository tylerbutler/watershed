//// Values and errors for the fixed SharedTree profile.

pub type FieldPath =
  List(String)

pub type TreeValue {
  StringValue(String)
  NumberValue(Float)
  BooleanValue(Bool)
  NullValue
  ObjectValue(schema_id: String, fields: List(#(String, TreeValue)))
}

pub type Edit {
  SetField(path: FieldPath, value: TreeValue)
  ClearField(path: FieldPath)
}

pub type TreeError {
  InvalidSchema(detail: String)
  InvalidEdit(path: FieldPath, detail: String)
  UnsupportedFormat(family: String, version: String)
  CorruptData(location: String, detail: String)
  InvalidHistory(detail: String)
}

pub type SequencePoint {
  SequencePoint(sequence_number: Int, index_in_batch: Int)
}
