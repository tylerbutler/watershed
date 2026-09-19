// A scripted `globalThis.WebSocket` for the signaling adapter tests.
//
// `crdt_signaling_js` reads `globalThis.WebSocket` at call time, so a test
// can install this class, drive each socket's lifecycle by hand — open it,
// close it, in whatever order the scenario needs — and restore the real
// constructor afterwards. Sockets are indexed in creation order.

let sockets = [];
let previous;

export function install() {
  previous = globalThis.WebSocket;
  sockets = [];
  globalThis.WebSocket = class {
    constructor(url) {
      this.url = url;
      this.readyState = 0;
      this.sent = [];
      sockets.push(this);
    }

    send(payload) {
      this.sent.push(payload);
    }

    close() {
      if (this.readyState === 3) return;
      this.readyState = 3;
      if (this.onclose) this.onclose({ code: 1000, reason: "" });
    }
  };
}

export function restore() {
  globalThis.WebSocket = previous;
  sockets = [];
}

export function openSocket(index) {
  const socket = sockets[index];
  socket.readyState = 1;
  if (socket.onopen) socket.onopen();
}

export function closeSocket(index, code) {
  const socket = sockets[index];
  socket.readyState = 3;
  if (socket.onclose) socket.onclose({ code, reason: "" });
}

export function socketCount() {
  return sockets.length;
}
