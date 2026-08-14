# Reference p2p services for local dev and the p2p smoke suite: the
# signaling service (tools/signaling/server.mjs) and the optional relay
# (tools/relay/server.mjs). Both are thin Node wrappers around Gleam modules
# built to the JavaScript target — `watershed/crdt_signaling` and
# `watershed/crdt_relay` — so this image builds that target once and ships it
# beside a minimal Node runtime. Neither process parses, logs, or stores a
# document envelope; see the header comment in each server file for what it
# does and does not do.
#
# One image, two commands — compose selects which server runs via `command:`
# (see docker-compose.p2p.yml).
#
#   docker build -t watershed-p2p-services -f tools/Dockerfile .
#   docker run --rm -p 4400:4400 watershed-p2p-services
#   docker run --rm -p 4500:4500 -v relay-data:/data/relay watershed-p2p-services \
#     node tools/relay/server.mjs --port 4500 --host 0.0.0.0 --data /data/relay

FROM ghcr.io/gleam-lang/gleam:v1.18.0-erlang-alpine AS build
WORKDIR /app
# `signet`, `spillway`, and `aquamarine` in gleam.toml are git dependencies
# (see the comment there), so `gleam deps download` needs `git` on PATH —
# the base image does not ship it.
RUN apk add --no-cache git
COPY gleam.toml manifest.toml ./
COPY src ./src
RUN gleam deps download && gleam build --target javascript

FROM node:22-alpine
WORKDIR /app
# Only `ws` is needed at runtime: `phoenix` (the root package.json's other
# dependency) is the browser DDS client's peer dependency, not used by either
# reference service. Installed directly rather than via the root
# package.json/pnpm-lock.yaml, so this image does not need the rest of the
# pnpm workspace copied in just to resolve one package.
RUN npm install --no-save ws@8.21.0
COPY --from=build /app/build ./build
COPY tools/signaling ./tools/signaling
COPY tools/relay ./tools/relay
EXPOSE 4400 4500
CMD ["node", "tools/signaling/server.mjs", "--port", "4400", "--host", "0.0.0.0"]
