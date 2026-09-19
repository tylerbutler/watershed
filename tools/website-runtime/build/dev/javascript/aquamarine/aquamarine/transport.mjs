/// <reference types="./transport.d.mts" />
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $gluegun_error from "../../gluegun/gluegun/error.mjs";
import * as $message from "../../gluegun/gluegun/message.mjs";
import * as $websocket from "../../gluegun/gluegun/websocket.mjs";
import * as $error from "../aquamarine/error.mjs";
import { CustomType as $CustomType } from "../gleam.mjs";

export class Text extends $CustomType {
  constructor(text) {
    super();
    this.text = text;
  }
}
export const Frame$Text = (text) => new Text(text);
export const Frame$isText = (value) => value instanceof Text;
export const Frame$Text$text = (value) => value.text;
export const Frame$Text$0 = (value) => value.text;

export class Binary extends $CustomType {
  constructor(data) {
    super();
    this.data = data;
  }
}
export const Frame$Binary = (data) => new Binary(data);
export const Frame$isBinary = (value) => value instanceof Binary;
export const Frame$Binary$data = (value) => value.data;
export const Frame$Binary$0 = (value) => value.data;

export class Closed extends $CustomType {}
export const Frame$Closed$const = new Closed();
export const Frame$Closed = () => Frame$Closed$const;
export const Frame$isClosed = (value) => value instanceof Closed;

export class Transport extends $CustomType {
  constructor(send_text, receive, close) {
    super();
    this.send_text = send_text;
    this.receive = receive;
    this.close = close;
  }
}
export const Transport$Transport = (send_text, receive, close) =>
  new Transport(send_text, receive, close);
export const Transport$isTransport = (value) => value instanceof Transport;
export const Transport$Transport$send_text = (value) => value.send_text;
export const Transport$Transport$0 = (value) => value.send_text;
export const Transport$Transport$receive = (value) => value.receive;
export const Transport$Transport$1 = (value) => value.receive;
export const Transport$Transport$close = (value) => value.close;
export const Transport$Transport$2 = (value) => value.close;

/**
 * Map a Gluegun error onto Aquamarine's transport-error surface.
 * 
 * @ignore
 */
export function from_gluegun(err) {
  if (err instanceof $gluegun_error.Timeout) {
    return new $error.Transport($error.TransportError$Timeout$const);
  } else if (err instanceof $gluegun_error.ConnectionDown) {
    let reason = err[0];
    return new $error.Transport(new $error.ConnectionDown(reason));
  } else if (err instanceof $gluegun_error.ConnectionError) {
    let reason = err[0];
    return new $error.Transport(new $error.ConnectionError(reason));
  } else if (err instanceof $gluegun_error.StreamError) {
    let reason = err[0];
    return new $error.Transport(new $error.StreamError(reason));
  } else if (err instanceof $gluegun_error.InvalidOptions) {
    let reason = err[0];
    return new $error.Transport(new $error.InvalidOptions(reason));
  } else if (err instanceof $gluegun_error.InvalidMessage) {
    let reason = err[0];
    return new $error.Transport(new $error.InvalidMessage(reason));
  } else if (err instanceof $gluegun_error.ErlangError) {
    let reason = err[0];
    return new $error.Transport(new $error.ErlangError(reason));
  } else {
    let reason = err[0];
    return new $error.Transport(new $error.DecodeError(reason));
  }
}
