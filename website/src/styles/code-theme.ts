export const watershedCodeTheme = {
  name: "watershed-survey",
  type: "light",
  colors: {
    "editor.foreground": "var(--ink)",
    "editor.background": "var(--bg)",
  },
  tokenColors: [
    {
      scope: ["comment", "comment.unused.gleam"],
      settings: { foreground: "var(--muted)", fontStyle: "italic" },
    },
    {
      scope: ["keyword.control.gleam", "keyword", "storage"],
      settings: { foreground: "var(--overprint-deep)" },
    },
    {
      scope: ["keyword.operator.gleam", "keyword.operator"],
      settings: { foreground: "var(--muted)" },
    },
    {
      scope: [
        "entity.name.type.gleam",
        "entity.name.type",
        "support.type",
        "constant.language",
      ],
      settings: { foreground: "var(--waterline)" },
    },
    {
      scope: [
        "entity.name.function.gleam",
        "entity.name.function",
        "support.function",
      ],
      settings: { foreground: "var(--ink)" },
    },
    {
      scope: [
        "variable.parameter.gleam",
        "entity.name.namespace.gleam",
        "variable.parameter",
      ],
      settings: { foreground: "var(--overprint-deep)" },
    },
    {
      scope: ["string", "string.quoted.double.gleam"],
      settings: { foreground: "var(--waterline)" },
    },
    {
      scope: ["constant.character.escape.gleam", "constant.numeric"],
      settings: { foreground: "var(--overprint-deep)" },
    },
    {
      scope: ["punctuation", "meta.brace", "meta.delimiter"],
      settings: { foreground: "var(--muted)" },
    },
    {
      scope: ["entity.name.tag", "markup.heading"],
      settings: { foreground: "var(--overprint-deep)" },
    },
    {
      scope: ["entity.other.attribute-name", "support.constant"],
      settings: { foreground: "var(--waterline)" },
    },
  ],
};
