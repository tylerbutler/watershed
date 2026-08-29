//// The dice document's root tag — a tag and nothing else.
////
//// Dice is the untyped example on purpose: the root map holds whatever keys
//// the user types into the inspector, so there is no field to declare and no
//// record to decode. What it still needs is an *identity*, because
//// `Document(root)` is what stops a second app from viewing this same root map
//// through a foreign schema. A tag with no fields is exactly that identity.

/// Phantom tag naming the dice root map. Declared, never constructed.
pub type DiceDoc
