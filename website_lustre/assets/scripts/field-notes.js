function revealTargetNote() {
  if (!location.hash) return;
  const target = document.getElementById(
    decodeURIComponent(location.hash.slice(1)),
  );
  const note = target?.closest("details");
  if (!note || note.open) return;
  note.open = true;
  note.scrollIntoView();
}

revealTargetNote();
addEventListener("hashchange", revealTargetNote);
