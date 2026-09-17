export function lwwRaceTimestamp(wallClock, states) {
  return Math.max(
    wallClock,
    ...states.map((state) => state.last_seen + 1),
  );
}
