# Third-Party Notices

Watershed itself is MIT-licensed — see [`LICENSE`](LICENSE). This file lists
upstream JavaScript packages whose documented behavior watershed's Gleam
kernels are a **checked, mechanical port of** (no upstream source files are
copied or vendored into this repository; each port is reimplemented in Gleam
and validated against the upstream package as a behavioral oracle — see
`tools/shared-rich-text-oracle`). Their license notices are reproduced below
as required by their licenses.

## rich-text (`SharedRichText`)

- **Package:** [`rich-text@4.1.0`](https://www.npmjs.com/package/rich-text/v/4.1.0)
- **Repository:** <https://github.com/ottypes/rich-text>
- **Commit (`gitHead` pinned by the published 4.1.0 package):**
  `b53cd97690804e544370423ce27c6d852abb2c7f`
- **License:** MIT
- **Derived modules:** `src/watershed/rich_text.gleam`,
  `src/watershed/rich_text_kernel.gleam`,
  `src/watershed/rich_text/attribute_map.gleam`,
  `src/watershed/rich_text/op_iterator.gleam` (the Delta apply/compose/
  transform/invert algebra and its `type`/attribute-map/op-iterator support
  code)

```
The MIT License (MIT)

Copyright (c) 2014 Jason Chen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## quill-delta (`SharedRichText`)

- **Package:** [`quill-delta@4.2.1`](https://www.npmjs.com/package/quill-delta/v/4.2.1)
- **Repository:** <https://github.com/quilljs/delta>
- **Commit (`gitHead` pinned by the published 4.2.1 package):**
  `06ca777f67905ea6533272b2f88189ee06bb4197`
- **License:** MIT
- **Derived modules:** `src/watershed/rich_text.gleam` (the `Delta` document
  model: `insert`/`retain`/`delete` op normalization, `length`, `compose`,
  `transform`, `invert`, and `transformPosition`/`transformCursor`-equivalent
  selection transforms), which `rich-text@4.1.0` composes on top of

```
The MIT License (MIT)

Copyright (c) 2014 Jason Chen

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

## ot-json0 (`json0`/`SharedJsonOt`)

- **Package:** [`ot-json0`](https://www.npmjs.com/package/ot-json0) (referred
  to in this codebase by its source repository name, `ottypes/json0`)
- **Repository:** <https://github.com/ottypes/json0>
- **License:** ISC, per the published package's `license` field. The upstream
  repository does not publish a dedicated `LICENSE` file with its own
  copyright notice text; `package.json` lists the author as Joseph Gentle.
  The standard ISC permission notice is reproduced below with that
  attribution; no more specific copyright year is published upstream to cite.
- **Derived modules:** `src/watershed/json_ot.gleam` (the json0 JSON-value
  model, `apply`, `transform`, `compose`, `invert`),
  `src/watershed/json_ot_kernel.gleam` (the client-transform kernel riding
  that algebra)

```
ISC License

Copyright (c) Joseph Gentle

Permission to use, copy, modify, and/or distribute this software for any
purpose with or without fee is hereby granted, provided that the above
copyright notice and this permission notice appear in all copies.

THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY
AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM
LOSS OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
PERFORMANCE OF THIS SOFTWARE.
```
