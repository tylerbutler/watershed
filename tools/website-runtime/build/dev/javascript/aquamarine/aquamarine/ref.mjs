/// <reference types="./ref.d.mts" />
import * as $process from "../../gleam_erlang/gleam/erlang/process.mjs";
import * as $actor from "../../gleam_otp/gleam/otp/actor.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

class Counter extends $CustomType {
  constructor(subject) {
    super();
    this.subject = subject;
  }
}

class Next extends $CustomType {
  constructor(reply_to) {
    super();
    this.reply_to = reply_to;
  }
}

class Stop extends $CustomType {}
const Message$Stop$const = new Stop();
