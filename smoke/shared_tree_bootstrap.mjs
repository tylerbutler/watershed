const { check_bootstrap_tree_close } = await import(
  "../build/dev/javascript/watershed/watershed/shared_tree_runtime_js_test.mjs"
);
await check_bootstrap_tree_close();
