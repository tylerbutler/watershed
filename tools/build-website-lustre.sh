#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

(cd tools/source-snippets && gleam run -m source_snippets/cli -- ../../website_lustre/snippets.json ../../website_lustre/src/generated/snippets.json)
(cd tools/website-lustre-build && gleam export escript)

rm -rf "${repo_root}/website_lustre/build/static"
(cd watershed_lustre && gleam build)
gleam build --target javascript

builder="${repo_root}/tools/website-lustre-build/website_lustre_tools"
(cd website_lustre && "${builder}" build watershed_site/client/guide_race watershed_site/client/sudoku watershed_site/client/directory watershed_site/client/counter_bug watershed_site/client/json_ot watershed_site/client/mv_register watershed_site/client/rich_text watershed_site/client/sequence)
(cd website_lustre && "${builder}" build watershed_site/client/structure_sheet)
(cd website_lustre && "${builder}" build watershed_site/client/text)
(cd website_lustre && "${builder}" build watershed_site/client/home)
(cd website_lustre && gleam run -m watershed_site/build)
