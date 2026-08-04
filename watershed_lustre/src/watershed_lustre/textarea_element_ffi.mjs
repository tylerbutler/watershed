// The single unsafe seam in `watershed_lustre/textarea_element`.
//
// A live `SharedText` handle crosses the custom-element property boundary as
// an opaque JavaScript value: typed out on the host side (`SharedText` posing
// as `Json` so `attribute.property` will carry it), and typed back in on the
// component side after the decoder has checked it has a handle's shape. Both
// directions are the identity at runtime — the coercion is entirely in the
// types, which is why it lives here and nowhere else.
export const identity = (value) => value;
