# Lustre website pilot

This package is the in-progress replacement for `/guide/race/`. The Astro
site under `website/` remains the production site.

Lustre SSG 0.12 is not published on Hex yet. The dependency is pinned to
upstream commit `2992bf78179d1be2876f834f0d923003f7f43f44`, with its compatible
TOML parser, rather than tracking a moving branch.

Run the package tests with `gleam test --target javascript`.
