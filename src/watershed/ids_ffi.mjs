// UUID generation for the JavaScript target. `globalThis.crypto.randomUUID`
// is available in every browser (secure contexts, including localhost) and in
// Node 19+, so no dependency on `node:crypto` — which would break browser
// bundling — is needed.

export function uuidV4() {
  return globalThis.crypto.randomUUID();
}
