# Pinned Fluid reference source

Source: [microsoft/FluidExamples, item-counter](https://github.com/microsoft/FluidExamples/tree/396454d692950f29c9965cf1190678cc6a227d23/item-counter)

Commit: `396454d692950f29c9965cf1190678cc6a227d23`

These four reference files come from the example linked as **Simple SharedTree
Example** on <https://fluidframework.com/docs/start/examples>. The original
copyright notices and [MIT license](LICENSE) are retained. The upstream package
at this revision requests Fluid `^3.1.0`; this snapshot does not claim full
watershed compatibility with that SDK release.

Only standalone `// docs:snippet-start ...` and `// docs:snippet-end ...` lines
have been added. Removing those lines reproduces the upstream bytes. Do not
format these reference files. The website's offline provenance test verifies
the original digests:

| Original path under `item-counter/` | SHA-256 before markers |
| --- | --- |
| `src/schema.ts` | `b94b5ed4619bd5c758d9341a994a725d5cdf043964a3da20c14f0be095a8bc33` |
| `src/index.tsx` | `2438b3e105ea461dfe35efeff68c17ae109940da7fe45ff59d74ad0e0b27ba31` |
| `src/react_app.tsx` | `2bbc732ff8b10664967f50c778cfbebd460de484032d24957cfaefad4935f254` |
| `src/infra/fluid.ts` | `d18f69efad2d5f26eb0d793e66f2db88230753b250686e262954de6f904e27ae` |

This is intentionally not a complete Fluid project. It is neither compiled
with the Gleam app nor imported into the website runtime. To run the Fluid
version, use the complete upstream project and its own instructions.

To update the reference, choose a reviewed commit, replace the four original
files and license, record their new digests here and in the provenance test,
and reapply the extraction markers. Review behavior and page explanations
alongside the source update. Website builds never download these files.
