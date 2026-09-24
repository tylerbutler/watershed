export async function waitUntil(check) {
  const deadline = Date.now() + 10_000;
  while (!check()) {
    if (Date.now() >= deadline) return false;
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
  return true;
}
