const {
  check_bootstrap_tree_close,
  check_datastore_alias_claims,
  check_datastore_alias_reconnect_timeout,
} = await import(
  "../build/dev/javascript/watershed/watershed/shared_tree_runtime_js_test.mjs"
);
const { shared_tree_map_facade_js_view_lifecycle_test } = await import(
  "../build/dev/javascript/watershed/watershed/shared_tree_map_facade_test.mjs"
);
await check_bootstrap_tree_close();
await check_datastore_alias_claims();
await check_datastore_alias_reconnect_timeout();
shared_tree_map_facade_js_view_lifecycle_test();
