const { check_bootstrap_tree_close } = await import(
  "../build/dev/javascript/watershed/watershed/shared_tree_runtime_js_test.mjs"
);
const { shared_tree_map_facade_js_view_lifecycle_test } = await import(
  "../build/dev/javascript/watershed/watershed/shared_tree_map_facade_test.mjs"
);
await check_bootstrap_tree_close();
shared_tree_map_facade_js_view_lifecycle_test();
