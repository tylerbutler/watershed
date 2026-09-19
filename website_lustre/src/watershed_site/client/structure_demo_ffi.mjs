export function familySlug() {
  return document.querySelector("[data-structure-family]")?.dataset
    .structureFamily ?? "";
}
