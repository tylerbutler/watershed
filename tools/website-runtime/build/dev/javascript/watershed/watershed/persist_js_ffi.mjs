const DATABASE = "watershed";
const STORE = "snapshots";
const VERSION = 1;

function detail(error) {
  if (error instanceof DOMException) {
    return `${error.name}: ${error.message}`;
  }
  return error instanceof Error ? error.message : String(error);
}

function open(onError) {
  let request;
  try {
    request = indexedDB.open(DATABASE, VERSION);
  } catch (error) {
    onError(detail(error));
    return null;
  }

  request.onupgradeneeded = () => {
    const database = request.result;
    if (!database.objectStoreNames.contains(STORE)) {
      database.createObjectStore(STORE);
    }
  };
  request.onerror = () => onError(detail(request.error));
  request.onblocked = () => onError("IndexedDB upgrade was blocked");
  return request;
}

export function getSnapshot(key, onMissing, onFound, onError) {
  let settled = false;
  let database = null;
  const finish = (callback, value) => {
    if (settled) return;
    settled = true;
    if (database !== null) {
      database.close();
      database = null;
    }
    callback(value);
  };
  const fail = (error) => finish(onError, error);
  const request = open(fail);
  if (request === null) return;

  request.onsuccess = () => {
    database = request.result;
    if (settled) {
      database.close();
      return;
    }
    let transaction;
    try {
      transaction = database.transaction(STORE, "readonly");
      const get = transaction.objectStore(STORE).get(key);
      get.onsuccess = () => {
        if (get.result === undefined) finish(onMissing);
        else finish(onFound, get.result);
      };
      get.onerror = () => fail(detail(get.error));
    } catch (error) {
      fail(detail(error));
    }
  };
}

export function updateSnapshot(key, transform, onOk, onAbort, onError) {
  let settled = false;
  let database = null;
  let failure = null;
  const finish = (callback, value) => {
    if (settled) return;
    settled = true;
    if (database !== null) {
      database.close();
      database = null;
    }
    callback(value);
  };
  const fail = (error) => finish(onError, error);
  const request = open(fail);
  if (request === null) return;

  request.onsuccess = () => {
    database = request.result;
    if (settled) {
      database.close();
      return;
    }
    let transaction;
    let decision = "pending";
    try {
      transaction = database.transaction(STORE, "readwrite");
      transaction.oncomplete = () => {
        finish(onOk);
      };
      transaction.onerror = (event) => {
        if (decision === "abort") {
          event.preventDefault();
          return;
        }
        fail(detail(transaction.error ?? "IndexedDB transaction failed"));
      };
      transaction.onabort = () => {
        if (decision === "abort") {
          finish(onAbort);
          return;
        }
        fail(failure ?? detail(transaction.error ?? "IndexedDB transaction aborted"));
      };

      const read = transaction.objectStore(STORE).get(key);
      read.onerror = () => fail(detail(read.error));
      read.onsuccess = () => {
        const write = (value) => {
          if (decision !== "pending") return;
          decision = "commit";
          try {
            transaction.objectStore(STORE).put(value, key);
          } catch (error) {
            decision = "error";
            failure = detail(error);
            try {
              transaction.abort();
            } catch (_abortError) {
              fail(failure);
            }
          }
        };

        const abort = () => {
          if (decision !== "pending") return;
          decision = "abort";
          try {
            transaction.abort();
          } catch (error) {
            failure = detail(error);
            decision = "error";
            fail(failure);
          }
        };

        try {
          transform(
            read.result !== undefined,
            read.result === undefined ? "" : read.result,
            write,
            abort,
          );
          if (decision === "pending") {
            failure = "storage update finished without writing or aborting";
            decision = "error";
            try {
              transaction.abort();
            } catch (_abortError) {
              fail(failure);
            }
          }
        } catch (error) {
          failure = detail(error);
          decision = "error";
          try {
            transaction.abort();
          } catch (_abortError) {
            fail(failure);
          }
        }
      };
    } catch (error) {
      fail(detail(error));
    }
  };
}

export function listenPagehide(action) {
  globalThis.addEventListener("pagehide", action);
  return () => globalThis.removeEventListener("pagehide", action);
}
