// The app-shell layer of the offline story, and nothing more: cache-first
// for the built bundle so a previously visited tab reopens the full UI with
// no network and no relay. Service workers cannot intercept WebSockets, so
// the collaboration path is untouched — and no other request is intercepted
// either.
//
// The cache name carries the bundle's content hash, stamped at build time
// (scripts/stamp-sw.mjs), so a new build gets a new cache and `activate`
// drops the old one.
const CACHE = "mdnotes-__BUILD_HASH__";

const SHELL = [
  "./",
  "./index.html",
  "./dist/markdown_notes_lustre.mjs",
  // The label face ships with the shell: a panel whose lettering only arrives
  // online is not offline-first, it just looks it on a warm cache.
  "./fonts/saira-latin-wdth-normal.woff2",
  "./manifest.webmanifest",
  "./icon-192.png",
  "./icon-512.png",
];

self.addEventListener("install", (event) => {
  event.waitUntil(
    caches.open(CACHE).then((cache) => cache.addAll(SHELL)).then(() => self.skipWaiting()),
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    caches
      .keys()
      .then((keys) =>
        Promise.all(keys.filter((key) => key !== CACHE).map((key) => caches.delete(key))),
      )
      .then(() => self.clients.claim()),
  );
});

self.addEventListener("fetch", (event) => {
  const url = new URL(event.request.url);
  const isShell =
    event.request.method === "GET" &&
    url.origin === self.location.origin &&
    SHELL.some((path) => url.pathname.endsWith(path.slice(1)) || (path === "./" && url.pathname === "/"));
  if (!isShell) return;
  // ignoreSearch: the app carries its document id in the query string, and
  // the cached shell must serve regardless of which document the tab is on.
  event.respondWith(
    caches
      .match(event.request, { ignoreSearch: true })
      .then((hit) => hit ?? fetch(event.request)),
  );
});
