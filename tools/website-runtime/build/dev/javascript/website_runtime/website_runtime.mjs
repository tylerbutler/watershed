/// <reference types="./website_runtime.d.mts" />
import * as $dict from "../gleam_stdlib/gleam/dict.mjs";
import * as $list from "../gleam_stdlib/gleam/list.mjs";
import * as $result from "../gleam_stdlib/gleam/result.mjs";
import * as $watershed from "../watershed/watershed.mjs";
import * as $sluice_js from "../watershed/watershed/sluice_js.mjs";
import { Ok, Error, CustomType as $CustomType } from "./gleam.mjs";

class Client extends $CustomType {
  constructor(document) {
    super();
    this.document = document;
  }
}

class Runtime extends $CustomType {
  constructor(sluice, clients) {
    super();
    this.sluice = sluice;
    this.clients = clients;
  }
}

export function start(tenant, document, client_ids) {
  let sluice = $sluice_js.start(tenant, document);
  let clients = $list.fold(
    client_ids,
    $dict.new$(),
    (clients, id) => {
      return $dict.insert(
        clients,
        id,
        new Client($sluice_js.connect(sluice, id)),
      );
    },
  );
  return new Ok(new Runtime(sluice, clients));
}

export function client(runtime, id) {
  let $ = $dict.get(runtime.clients, id);
  if ($ instanceof Ok) {
    return $;
  } else {
    return new Error("unknown client: " + id);
  }
}

export function settle(runtime) {
  return $sluice_js.settle(runtime.sluice);
}

export function peek(runtime) {
  return $sluice_js.peek_info(runtime.sluice);
}

export function step(runtime) {
  return $sluice_js.step_info(runtime.sluice);
}

export function pending(runtime) {
  return $sluice_js.pending(runtime.sluice);
}

export function sequence_number(runtime) {
  return $sluice_js.sequence_number(runtime.sluice);
}

export function pause(runtime, id) {
  return $result.try$(
    client(runtime, id),
    (_use0) => {
      let document$1 = _use0.document;
      $sluice_js.pause(runtime.sluice, document$1);
      return new Ok(undefined);
    },
  );
}

export function resume(runtime, id) {
  return $result.try$(
    client(runtime, id),
    (_use0) => {
      let document$1 = _use0.document;
      $sluice_js.resume(runtime.sluice, document$1);
      return new Ok(undefined);
    },
  );
}

export function document(client) {
  return client.document;
}
