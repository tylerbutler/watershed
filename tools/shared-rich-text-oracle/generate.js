const fs = require('node:fs');
const path = require('node:path');

const Delta = require('quill-delta');
const { type } = require('rich-text');

const repoRoot = path.resolve(__dirname, '../..');
const fixtureDir = path.join(repoRoot, 'test/fixtures/shared_rich_text');

function D(build) {
  const delta = new Delta();
  build(delta);
  return delta;
}

function serializeDelta(delta) {
  return JSON.parse(JSON.stringify(type.serialize(type.normalize(delta))));
}

function clone(value) {
  return JSON.parse(JSON.stringify(value));
}

function transformCursor(delta, cursor) {
  return type.transformCursor(cursor.index, delta, cursor.isOwnOp);
}

function transformSelection(delta, selection) {
  return type.transformPresence(
    { index: selection.index, length: selection.length },
    delta,
    selection.isOwnOp,
  );
}

function buildFixture(spec) {
  const base = spec.base;
  const a = spec.deltas.a;
  const b = spec.deltas.b;
  const composed = b ? type.compose(a, b) : null;

  const fixture = {
    formatVersion: 1,
    name: spec.name,
    description: spec.description,
    base: serializeDelta(base),
    deltas: {
      a: serializeDelta(a),
    },
    normalized: {
      base: serializeDelta(base),
      deltas: {
        a: serializeDelta(a),
      },
    },
    apply: {
      a: serializeDelta(type.apply(base, a)),
    },
    inverse: {
      a: serializeDelta(a.invert(base)),
    },
    cursor: {},
    selection: {},
  };

  if (b) {
    fixture.deltas.b = serializeDelta(b);
    fixture.normalized.deltas.b = serializeDelta(b);
    fixture.apply.b = serializeDelta(type.apply(base, b));
    fixture.inverse.b = serializeDelta(b.invert(base));
    fixture.compose = serializeDelta(composed);
    fixture.normalized.compose = serializeDelta(composed);
    fixture.transform = {
      left: serializeDelta(type.transform(a, b, 'left')),
      right: serializeDelta(type.transform(a, b, 'right')),
    };
    fixture.inverse.compose = serializeDelta(composed.invert(base));
    if (spec.applyCompose) {
      fixture.apply.compose = serializeDelta(type.apply(base, composed));
    }
  }

  const through = spec.cursor.through;
  const cursorDelta = through === 'compose' ? composed : a;
  fixture.cursor = {
    through,
    index: spec.cursor.index,
    isOwnOp: spec.cursor.isOwnOp,
    result: transformCursor(cursorDelta, spec.cursor),
  };

  const selectionThrough = spec.selection.through;
  const selectionDelta = selectionThrough === 'compose' ? composed : a;
  fixture.selection = {
    through: selectionThrough,
    index: spec.selection.index,
    length: spec.selection.length,
    isOwnOp: spec.selection.isOwnOp,
    result: clone(transformSelection(selectionDelta, spec.selection)),
  };

  return fixture;
}

const scenarios = [
  {
    file: '01-plain-text-insert.json',
    name: 'plain-text-insert',
    description: 'Insert plain ASCII text into a plain text document.',
    base: D((d) => d.insert('Hello world')),
    deltas: {
      a: D((d) => d.retain(6).insert('beautiful ')),
    },
    cursor: { through: 'a', index: 6, isOwnOp: true },
    selection: { through: 'a', index: 0, length: 11, isOwnOp: false },
  },
  {
    file: '02-combining-mark-delete.json',
    name: 'combining-mark-delete',
    description: 'Delete a single combining mark using UTF-16 offsets.',
    base: D((d) => d.insert('Café noir')),
    deltas: {
      a: D((d) => d.retain(4).delete(1)),
    },
    cursor: { through: 'a', index: 5, isOwnOp: false },
    selection: { through: 'a', index: 3, length: 3, isOwnOp: false },
  },
  {
    file: '03-supplementary-emoji-replace.json',
    name: 'supplementary-emoji-replace',
    description: 'Replace a supplementary emoji with mixed retain/delete/insert ops.',
    base: D((d) => d.insert('A😀B')),
    deltas: {
      a: D((d) => d.retain(1).delete(2).insert('x')),
    },
    cursor: { through: 'a', index: 3, isOwnOp: false },
    selection: { through: 'a', index: 0, length: 4, isOwnOp: false },
  },
  {
    file: '04-embed-replacement.json',
    name: 'embed-replacement',
    description: 'Replace an embed and preserve embed attributes.',
    base: D((d) =>
      d
        .insert('A')
        .insert({ image: 'cat.png' }, { alt: 'cat' })
        .insert('B'),
    ),
    deltas: {
      a: D((d) =>
        d
          .retain(1)
          .delete(1)
          .insert({ video: 'dog.mp4' }, { width: 640, height: 360 }),
      ),
    },
    cursor: { through: 'a', index: 1, isOwnOp: true },
    selection: { through: 'a', index: 0, length: 3, isOwnOp: false },
  },
  {
    file: '05-formatting-add-remove.json',
    name: 'formatting-add-remove',
    description: 'Add and remove inline formatting on an existing formatted span.',
    base: D((d) => d.insert('Hello ').insert('world', { bold: true })),
    deltas: {
      a: D((d) => d.retain(6).retain(5, { bold: null, italic: true })),
    },
    cursor: { through: 'a', index: 6, isOwnOp: false },
    selection: { through: 'a', index: 6, length: 5, isOwnOp: false },
  },
  {
    file: '06-same-position-insert.json',
    name: 'same-position-insert',
    description: 'Pin same-position insert tie-breaking for left/right transforms.',
    base: D((d) => d),
    deltas: {
      a: D((d) => d.insert('A')),
      b: D((d) => d.insert('B')),
    },
    applyCompose: true,
    cursor: { through: 'compose', index: 0, isOwnOp: true },
    selection: { through: 'compose', index: 0, length: 0, isOwnOp: true },
  },
  {
    file: '07-overlapping-deletes.json',
    name: 'overlapping-deletes',
    description: 'Pin overlapping delete rebases and inverse restoration.',
    base: D((d) => d.insert('abcdef')),
    deltas: {
      a: D((d) => d.retain(1).delete(3)),
      b: D((d) => d.retain(2).delete(3)),
    },
    cursor: { through: 'compose', index: 5, isOwnOp: false },
    selection: { through: 'compose', index: 1, length: 4, isOwnOp: false },
  },
  {
    file: '08-concurrent-formatting.json',
    name: 'concurrent-formatting',
    description: 'Resolve concurrent formatting with conflicting attribute changes.',
    base: D((d) => d.insert('hello', { bold: true })),
    deltas: {
      a: D((d) => d.retain(5, { bold: null, italic: true })),
      b: D((d) => d.retain(5, { bold: true, color: '#f00' })),
    },
    applyCompose: true,
    cursor: { through: 'compose', index: 2, isOwnOp: false },
    selection: { through: 'compose', index: 0, length: 5, isOwnOp: false },
  },
];

function fixtureText(fixture) {
  return JSON.stringify(fixture, null, 2) + '\n';
}

function expectedFiles() {
  return scenarios.map((spec) => [spec.file, fixtureText(buildFixture(spec))]);
}

function writeFixtures() {
  fs.mkdirSync(fixtureDir, { recursive: true });
  for (const [file, text] of expectedFiles()) {
    fs.writeFileSync(path.join(fixtureDir, file), text);
  }
}

function validateFixtures() {
  const expected = new Map(expectedFiles());
  const actualFiles = fs
    .readdirSync(fixtureDir)
    .filter((file) => file.endsWith('.json'))
    .sort();

  const expectedFilesSorted = [...expected.keys()].sort();
  if (JSON.stringify(actualFiles) !== JSON.stringify(expectedFilesSorted)) {
    throw new Error(
      `fixture file set mismatch:\nexpected ${expectedFilesSorted.join(', ')}\nactual   ${actualFiles.join(', ')}`,
    );
  }

  for (const file of actualFiles) {
    const actual = fs.readFileSync(path.join(fixtureDir, file), 'utf8');
    const wanted = expected.get(file);
    if (actual !== wanted) {
      throw new Error(`fixture mismatch: ${file}`);
    }
  }
}

const check = process.argv.includes('--check');

if (check) {
  validateFixtures();
  console.log(`validated ${scenarios.length} SharedRichText fixtures`);
} else {
  writeFixtures();
  console.log(`wrote ${scenarios.length} SharedRichText fixtures`);
}
