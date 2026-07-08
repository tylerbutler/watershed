// Reference (identity) equality for the JS sluice driver. `pause`/`resume`
// target a client by its `watershed_js` runtime; two distinct runtimes must
// never compare equal, so we use `===` (object identity) rather than Gleam's
// structural equality, which would deep-compare the mutable state cells.
export function referenceEquals(a, b) {
  return a === b;
}
