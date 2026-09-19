/// <reference types="./or_map_set_leaf.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $dict from "../../gleam_stdlib/gleam/dict.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { None, Some } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $set from "../../gleam_stdlib/gleam/set.mjs";
import * as $string from "../../gleam_stdlib/gleam/string.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $version_vector from "../../lattice_core/lattice_core/version_vector.mjs";
import * as $crdt from "../../lattice_maps/lattice_maps/crdt.mjs";
import * as $or_map from "../../lattice_maps/lattice_maps/or_map.mjs";
import * as $or_set from "../../lattice_sets/lattice_sets/or_set.mjs";
import {
  Ok,
  Error,
  toList,
  List$Empty$const as $List$Empty$const,
  CustomType as $CustomType,
} from "../gleam.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";

export class Clocks extends $CustomType {
  constructor(key_counter, member_counters) {
    super();
    this.key_counter = key_counter;
    this.member_counters = member_counters;
  }
}
export const Clocks$Clocks = (key_counter, member_counters) =>
  new Clocks(key_counter, member_counters);
export const Clocks$isClocks = (value) => value instanceof Clocks;
export const Clocks$Clocks$key_counter = (value) => value.key_counter;
export const Clocks$Clocks$0 = (value) => value.key_counter;
export const Clocks$Clocks$member_counters = (value) => value.member_counters;
export const Clocks$Clocks$1 = (value) => value.member_counters;

export class AddMember extends $CustomType {
  constructor(member) {
    super();
    this.member = member;
  }
}
export const Intent$AddMember = (member) => new AddMember(member);
export const Intent$isAddMember = (value) => value instanceof AddMember;
export const Intent$AddMember$member = (value) => value.member;
export const Intent$AddMember$0 = (value) => value.member;

export class RemoveMember extends $CustomType {
  constructor(member) {
    super();
    this.member = member;
  }
}
export const Intent$RemoveMember = (member) => new RemoveMember(member);
export const Intent$isRemoveMember = (value) => value instanceof RemoveMember;
export const Intent$RemoveMember$member = (value) => value.member;
export const Intent$RemoveMember$0 = (value) => value.member;

export class RemoveKey extends $CustomType {}
export const Intent$RemoveKey$const = new RemoveKey();
export const Intent$RemoveKey = () => Intent$RemoveKey$const;
export const Intent$isRemoveKey = (value) => value instanceof RemoveKey;

export class InvalidState extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const LeafError$InvalidState = (detail) => new InvalidState(detail);
export const LeafError$isInvalidState = (value) =>
  value instanceof InvalidState;
export const LeafError$InvalidState$detail = (value) => value.detail;
export const LeafError$InvalidState$0 = (value) => value.detail;

export class CounterExhausted extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const LeafError$CounterExhausted = (detail) =>
  new CounterExhausted(detail);
export const LeafError$isCounterExhausted = (value) =>
  value instanceof CounterExhausted;
export const LeafError$CounterExhausted$detail = (value) => value.detail;
export const LeafError$CounterExhausted$0 = (value) => value.detail;

export const LeafError$detail = (value) => value.detail;

class Snapshot extends $CustomType {
  constructor(author, spec, clock, entries) {
    super();
    this.author = author;
    this.spec = spec;
    this.clock = clock;
    this.entries = entries;
  }
}

class Entry extends $CustomType {
  constructor(key, generation, membership, value) {
    super();
    this.key = key;
    this.generation = generation;
    this.membership = membership;
    this.value = value;
  }
}

class VectorMetadata extends $CustomType {
  constructor(type_tag, version, clocks) {
    super();
    this.type_tag = type_tag;
    this.version = version;
    this.clocks = clocks;
  }
}

class SetMetadata extends $CustomType {
  constructor(native, counter, entries, tombstones) {
    super();
    this.native = native;
    this.counter = counter;
    this.entries = entries;
    this.tombstones = tombstones;
  }
}

class MapMetadata extends $CustomType {
  constructor(counter, key_entries, key_tombstones, mentioned_keys, values, bounds) {
    super();
    this.counter = counter;
    this.key_entries = key_entries;
    this.key_tombstones = key_tombstones;
    this.mentioned_keys = mentioned_keys;
    this.values = values;
    this.bounds = bounds;
  }
}

const safe_counter = 9_007_199_254_740_991;

function merge_error(error) {
  if (error instanceof $crdt.TypeMismatch) {
    let expected = error.expected;
    let found = error.found;
    return new InvalidState(
      ((("Expected " + expected) + ", found ") + found) + ".",
    );
  } else {
    return new InvalidState(
      "Invalid native OR-map operation: " + $string.inspect(error),
    );
  }
}

/**
 * Native generation floors preserve removal history.
 * 
 * @ignore
 */
export function merge(left, right) {
  let _pipe = $or_map.merge(left, right);
  return $result.map_error(_pipe, merge_error);
}

/**
 * Apply a native delta without discarding removal history.
 * 
 * @ignore
 */
export function apply_delta(map, delta) {
  let _pipe = $or_map.apply_delta(map, delta);
  return $result.map_error(_pipe, merge_error);
}

function snapshot_decoder() {
  let entry_decoder = $decode.field(
    "key",
    $decode.string,
    (key) => {
      return $decode.field(
        "generation",
        $json_ot.decoder(),
        (generation) => {
          return $decode.field(
            "membership",
            $decode.string,
            (membership) => {
              return $decode.field(
                "value",
                $decode.optional($decode.string),
                (value) => {
                  return $decode.success(
                    new Entry(key, generation, membership, value),
                  );
                },
              );
            },
          );
        },
      );
    },
  );
  return $decode.at(
    toList(["state"]),
    $decode.field(
      "replica_id",
      $decode.string,
      (author) => {
        return $decode.field(
          "spec",
          $decode.string,
          (spec) => {
            return $decode.field(
              "clock",
              $decode.int,
              (clock) => {
                return $decode.field(
                  "entries",
                  $decode.list(entry_decoder),
                  (entries) => {
                    return $decode.success(
                      new Snapshot(author, spec, clock, entries),
                    );
                  },
                );
              },
            );
          },
        );
      },
    ),
  );
}

function encode_snapshot(snapshot, delta) {
  let _pipe = $json.object(
    toList([
      [
        "type",
        $json.string(
          (() => {
            if (delta) {
              return "or_map_delta";
            } else {
              return "or_map";
            }
          })(),
        ),
      ],
      [
        "v",
        $json.int(
          (() => {
            if (delta) {
              return 2;
            } else {
              return 3;
            }
          })(),
        ),
      ],
      [
        "state",
        $json.object(
          toList([
            ["replica_id", $json.string(snapshot.author)],
            ["spec", $json.string(snapshot.spec)],
            ["clock", $json.int(snapshot.clock)],
            [
              "entries",
              $json.array(
                snapshot.entries,
                (entry) => {
                  return $json.object(
                    toList([
                      ["key", $json.string(entry.key)],
                      ["generation", $json_ot.to_json(entry.generation)],
                      ["membership", $json.string(entry.membership)],
                      [
                        "value",
                        (() => {
                          let $ = entry.value;
                          if ($ instanceof Some) {
                            let value = $[0];
                            return $json.string(value);
                          } else {
                            return $json.null$();
                          }
                        })(),
                      ],
                    ]),
                  );
                },
              ),
            ],
          ]),
        ),
      ],
    ]),
  );
  return $json.to_string(_pipe);
}

function codec_error(error) {
  return new InvalidState(
    "Invalid native OR-map metadata: " + $string.inspect(error),
  );
}

function require(condition, detail) {
  if (condition) {
    return new Ok(undefined);
  } else {
    return new Error(new InvalidState(detail));
  }
}

function valid_counter(counter) {
  return (counter >= 0) && (counter <= safe_counter);
}

function vector_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => {
          return $decode.then$(
            $decode.at(
              toList(["state", "clocks"]),
              $decode.dict($decode.string, $decode.int),
            ),
            (clocks) => {
              return $decode.success(
                new VectorMetadata(type_tag, version, clocks),
              );
            },
          );
        },
      );
    },
  );
}

function validate_vector(vector) {
  return require(
    ((vector.type_tag === "version_vector") && (vector.version === 1)) && $list.all(
      $dict.values(vector.clocks),
      valid_counter,
    ),
    "Invalid version vector.",
  );
}

function read_set(encoded) {
  let tag_decoder = $decode.field(
    "r",
    $decode.string,
    (author) => {
      return $decode.field(
        "c",
        $decode.int,
        (counter) => { return $decode.success([author, counter]); },
      );
    },
  );
  let decoder = $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => {
          return $decode.field(
            "state",
            $decode.field(
              "replica_id",
              $decode.string,
              (_) => {
                return $decode.field(
                  "counter",
                  $decode.int,
                  (counter) => {
                    return $decode.field(
                      "entries",
                      (() => {
                        if (version === 3) {
                          return $decode.then$(
                            $decode.list(
                              $decode.field(
                                "value",
                                $decode.string,
                                (value) => {
                                  return $decode.field(
                                    "tags",
                                    $decode.list(tag_decoder),
                                    (tags) => {
                                      return $decode.success([value, tags]);
                                    },
                                  );
                                },
                              ),
                            ),
                            (entries) => {
                              let unique = $dict.from_list(entries);
                              let $ = $dict.size(unique) === $list.length(
                                entries,
                              );
                              if ($) {
                                return $decode.success(unique);
                              } else {
                                return $decode.failure(
                                  unique,
                                  "distinct OR-set members",
                                );
                              }
                            },
                          );
                        } else {
                          return $decode.dict(
                            $decode.string,
                            $decode.list(tag_decoder),
                          );
                        }
                      })(),
                      (entries) => {
                        return $decode.optional_field(
                          "tombstones",
                          $List$Empty$const,
                          $decode.list(tag_decoder),
                          (tombstones) => {
                            return $decode.optional_field(
                              "pruned",
                              new VectorMetadata(
                                "version_vector",
                                1,
                                $dict.new$(),
                              ),
                              vector_decoder(),
                              (pruned) => {
                                return $decode.success(
                                  [counter, entries, tombstones, pruned],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
            (state) => { return $decode.success([type_tag, version, state]); },
          );
        },
      );
    },
  );
  return $result.try$(
    (() => {
      let _pipe = $json.parse(encoded, decoder);
      return $result.map_error(_pipe, codec_error);
    })(),
    (_use0) => {
      let type_tag;
      let version;
      let counter;
      let entries;
      let tombstones;
      let pruned;
      type_tag = _use0[0];
      version = _use0[1];
      counter = _use0[2][0];
      entries = _use0[2][1];
      tombstones = _use0[2][2];
      pruned = _use0[2][3];
      return $result.try$(
        require(
          (type_tag === "or_set") && (((version === 1) || (version === 2)) || (version === 3)),
          "Expected OR-set v1, v2, or v3.",
        ),
        (_) => {
          return $result.try$(
            validate_vector(pruned),
            (_) => {
              return $result.try$(
                require(
                  $dict.size(pruned.clocks) === 0,
                  "OR-set pruning is not supported.",
                ),
                (_) => {
                  return $result.try$(
                    require(valid_counter(counter), "Invalid OR-set counter."),
                    (_) => {
                      let _block;
                      let _pipe = $dict.values(entries);
                      _block = $list.flatten(_pipe);
                      let live = _block;
                      return $result.try$(
                        require(
                          $list.all(
                            $list.append(live, tombstones),
                            (dot) => {
                              return ((dot[1] > 0) && (dot[1] <= counter)) && (dot[1] <= safe_counter);
                            },
                          ),
                          "OR-set tags must have positive safe counters at or below the state counter.",
                        ),
                        (_) => {
                          return $result.try$(
                            require(
                              $set.is_empty(
                                $set.intersection(
                                  $set.from_list(live),
                                  $set.from_list(tombstones),
                                ),
                              ),
                              "An OR-set tag cannot be both live and removed.",
                            ),
                            (_) => {
                              return $result.try$(
                                $list.try_fold(
                                  $dict.to_list(entries),
                                  $dict.new$(),
                                  (owners, pair) => {
                                    return $result.try$(
                                      require(
                                        !$list.is_empty(pair[1]),
                                        "A live OR-set member must have a tag.",
                                      ),
                                      (_) => {
                                        return $list.try_fold(
                                          pair[1],
                                          owners,
                                          (owners, dot) => {
                                            let $ = $dict.get(owners, dot);
                                            if ($ instanceof Ok) {
                                              let member = $[0];
                                              if (member !== pair[0]) {
                                                return new Error(
                                                  new InvalidState(
                                                    "An OR-set tag belongs to distinct live members.",
                                                  ),
                                                );
                                              } else {
                                                return new Ok(
                                                  $dict.insert(
                                                    owners,
                                                    dot,
                                                    pair[0],
                                                  ),
                                                );
                                              }
                                            } else {
                                              return new Ok(
                                                $dict.insert(
                                                  owners,
                                                  dot,
                                                  pair[0],
                                                ),
                                              );
                                            }
                                          },
                                        );
                                      },
                                    );
                                  },
                                ),
                                (_) => {
                                  return $result.try$(
                                    (() => {
                                      let _block$1;
                                      if (version === 3) {
                                        _block$1 = $or_set.from_json_with(
                                          encoded,
                                          $decode.string,
                                        );
                                      } else {
                                        _block$1 = $or_set.from_json(encoded);
                                      }
                                      let _pipe$1 = _block$1;
                                      return $result.map_error(
                                        _pipe$1,
                                        codec_error,
                                      );
                                    })(),
                                    (native) => {
                                      return new Ok(
                                        new SetMetadata(
                                          native,
                                          counter,
                                          entries,
                                          tombstones,
                                        ),
                                      );
                                    },
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function read_legacy_map(encoded) {
  let value_decoder = $decode.field(
    "key",
    $decode.string,
    (key) => {
      return $decode.field(
        "crdt",
        $decode.string,
        (value) => { return $decode.success([key, value]); },
      );
    },
  );
  let decoder = $decode.field(
    "type",
    $decode.string,
    (type_tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => {
          return $decode.field(
            "state",
            $decode.field(
              "replica_id",
              $decode.string,
              (_) => {
                return $decode.field(
                  "crdt_spec",
                  $decode.string,
                  (spec) => {
                    return $decode.field(
                      "key_set",
                      $decode.string,
                      (keys) => {
                        return $decode.field(
                          "values",
                          $decode.list(value_decoder),
                          (values) => {
                            return $decode.optional_field(
                              "remove_bounds",
                              $dict.new$(),
                              $decode.dict($decode.string, vector_decoder()),
                              (bounds) => {
                                return $decode.success(
                                  [spec, keys, values, bounds],
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
            (state) => { return $decode.success([type_tag, version, state]); },
          );
        },
      );
    },
  );
  return $result.try$(
    (() => {
      let _pipe = $json.parse(encoded, decoder);
      return $result.map_error(_pipe, codec_error);
    })(),
    (_use0) => {
      let type_tag;
      let version;
      let spec;
      let keys;
      let values;
      let bounds;
      type_tag = _use0[0];
      version = _use0[1];
      spec = _use0[2][0];
      keys = _use0[2][1];
      values = _use0[2][2];
      bounds = _use0[2][3];
      return $result.try$(
        require(
          (type_tag === "or_map") && ((version === 1) || (version === 2)),
          "Invalid OR-map envelope type or version.",
        ),
        (_) => {
          return $result.try$(
            require(spec === "or_set", "Expected or_set value spec."),
            (_) => {
              let value_keys = $list.map(values, (pair) => { return pair[0]; });
              return $result.try$(
                require(
                  $list.length(value_keys) === $set.size(
                    $set.from_list(value_keys),
                  ),
                  "Duplicate OR-map value keys.",
                ),
                (_) => {
                  return $result.try$(
                    read_set(keys),
                    (keys) => {
                      return $result.try$(
                        $list.try_map($dict.values(bounds), validate_vector),
                        (_) => {
                          return $result.try$(
                            $list.try_map(
                              values,
                              (pair) => {
                                return $result.try$(
                                  read_set(pair[1]),
                                  (value) => { return new Ok([pair[0], value]); },
                                );
                              },
                            ),
                            (values) => {
                              let values$1 = $dict.from_list(values);
                              return $result.try$(
                                require(
                                  $list.all(
                                    $dict.keys(keys.entries),
                                    (key) => {
                                      return $dict.has_key(values$1, key);
                                    },
                                  ),
                                  "An active OR-map key has no set value.",
                                ),
                                (_) => {
                                  return new Ok(
                                    new MapMetadata(
                                      keys.counter,
                                      keys.entries,
                                      keys.tombstones,
                                      $list.append(
                                        $dict.keys(keys.entries),
                                        $list.append(
                                          value_keys,
                                          $dict.keys(bounds),
                                        ),
                                      ),
                                      values$1,
                                      bounds,
                                    ),
                                  );
                                },
                              );
                            },
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function read_map(encoded, delta) {
  return $result.try$(
    (() => {
      let _block;
      if (delta) {
        let _pipe = $or_map.delta_from_json(encoded);
        _block = $result.replace(_pipe, undefined);
      } else {
        let _pipe = $or_map.from_json(encoded);
        _block = $result.replace(_pipe, undefined);
      }
      let _pipe = _block;
      return $result.map_error(_pipe, codec_error);
    })(),
    (_) => {
      return $result.try$(
        (() => {
          let _pipe = $json.parse(encoded, snapshot_decoder());
          return $result.map_error(_pipe, codec_error);
        })(),
        (snapshot) => {
          return $result.try$(
            (() => {
              let _pipe = $crdt.spec_from_json_with(
                snapshot.spec,
                $decode.string,
              );
              return $result.map_error(_pipe, codec_error);
            })(),
            (spec) => {
              return $result.try$(
                require(
                  spec instanceof $crdt.OrSetSpec,
                  "Expected or_set value spec.",
                ),
                (_) => {
                  return $result.try$(
                    $list.try_map(
                      snapshot.entries,
                      (entry) => {
                        return $result.try$(
                          read_set(entry.membership),
                          (membership) => {
                            return new Ok([entry.key, membership]);
                          },
                        );
                      },
                    ),
                    (memberships) => {
                      let counter = $list.fold(
                        memberships,
                        snapshot.clock,
                        (counter, pair) => {
                          return $int.max(counter, pair[1].counter);
                        },
                      );
                      let key_entries = $list.fold(
                        memberships,
                        $dict.new$(),
                        (entries, pair) => {
                          return $dict.combine(
                            entries,
                            pair[1].entries,
                            $list.append,
                          );
                        },
                      );
                      let key_tombstones = $list.flat_map(
                        memberships,
                        (pair) => { return pair[1].tombstones; },
                      );
                      return $result.try$(
                        $list.try_fold(
                          snapshot.entries,
                          $dict.new$(),
                          (values, entry) => {
                            let $ = entry.value;
                            if ($ instanceof Some) {
                              let encoded$1 = $[0];
                              return $result.try$(
                                (() => {
                                  if (delta) {
                                    return $result.try$(
                                      (() => {
                                        let _pipe = $crdt.delta_from_json_with(
                                          encoded$1,
                                          $decode.string,
                                        );
                                        return $result.map_error(
                                          _pipe,
                                          codec_error,
                                        );
                                      })(),
                                      (change) => {
                                        if (change instanceof $crdt.StateDelta) {
                                          let $1 = change[0];
                                          if ($1 instanceof $crdt.CrdtOrSet) {
                                            let _pipe = $json.parse(
                                              encoded$1,
                                              $decode.at(
                                                toList(["state", "payload"]),
                                                $decode.string,
                                              ),
                                            );
                                            return $result.map_error(
                                              _pipe,
                                              codec_error,
                                            );
                                          } else {
                                            return new Error(
                                              new InvalidState(
                                                "Expected a complete OR-set leaf delta.",
                                              ),
                                            );
                                          }
                                        } else {
                                          return new Error(
                                            new InvalidState(
                                              "Expected a complete OR-set leaf delta.",
                                            ),
                                          );
                                        }
                                      },
                                    );
                                  } else {
                                    return new Ok(encoded$1);
                                  }
                                })(),
                                (child) => {
                                  return $result.try$(
                                    read_set(child),
                                    (leaf) => {
                                      return new Ok(
                                        $dict.insert(values, entry.key, leaf),
                                      );
                                    },
                                  );
                                },
                              );
                            } else {
                              return new Ok(values);
                            }
                          },
                        ),
                        (values) => {
                          let _block;
                          let _pipe = memberships;
                          let _pipe$1 = $list.filter_map(
                            _pipe,
                            (pair) => {
                              let $ = $list.is_empty(pair[1].tombstones);
                              if ($) {
                                return new Error(undefined);
                              } else {
                                return new Ok(
                                  [
                                    pair[0],
                                    new VectorMetadata(
                                      "version_vector",
                                      1,
                                      $list.fold(
                                        pair[1].tombstones,
                                        $dict.new$(),
                                        (clocks, dot) => {
                                          return $dict.insert(
                                            clocks,
                                            dot[0],
                                            $int.max(
                                              $result.unwrap(
                                                $dict.get(clocks, dot[0]),
                                                0,
                                              ),
                                              dot[1],
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              }
                            },
                          );
                          _block = $dict.from_list(_pipe$1);
                          let bounds = _block;
                          return new Ok(
                            new MapMetadata(
                              counter,
                              key_entries,
                              key_tombstones,
                              $list.map(
                                snapshot.entries,
                                (entry) => { return entry.key; },
                              ),
                              values,
                              bounds,
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

function checked_clocks(clocks) {
  return $result.try$(
    require(
      valid_counter(clocks.key_counter) && $list.all(
        $dict.values(clocks.member_counters),
        valid_counter,
      ),
      "Invalid OR-map counter floor.",
    ),
    (_) => {
      return new Ok(
        new Clocks(
          $list.fold(
            $dict.values(clocks.member_counters),
            clocks.key_counter,
            $int.max,
          ),
          clocks.member_counters,
        ),
      );
    },
  );
}

function observe_metadata(clocks, metadata) {
  return $result.try$(
    checked_clocks(clocks),
    (clocks) => {
      let members = $dict.fold(
        metadata.values,
        clocks.member_counters,
        (counters, key, leaf) => {
          return $dict.insert(
            counters,
            key,
            $int.max($result.unwrap($dict.get(counters, key), 0), leaf.counter),
          );
        },
      );
      let _block;
      let _pipe = metadata.bounds;
      let _pipe$1 = $dict.values(_pipe);
      let _pipe$2 = $list.flat_map(
        _pipe$1,
        (bound) => { return $dict.values(bound.clocks); },
      );
      _block = $list.fold(_pipe$2, 0, $int.max);
      let bounds = _block;
      return checked_clocks(
        new Clocks(
          $int.max(clocks.key_counter, $int.max(metadata.counter, bounds)),
          members,
        ),
      );
    },
  );
}

export function observe_state(clocks, map) {
  return $result.try$(
    read_map(
      (() => {
        let _pipe = $or_map.to_json(map);
        return $json.to_string(_pipe);
      })(),
      false,
    ),
    (metadata) => { return observe_metadata(clocks, metadata); },
  );
}

/**
 * Reserve only the authoring cursor. Do not copy pending tags or values.
 * 
 * @ignore
 */
export function retain_counter_floor(map, clocks, replica) {
  return $result.try$(
    observe_state(clocks, map),
    (clocks) => {
      return $result.try$(
        (() => {
          let _pipe = $json.parse(
            (() => {
              let _pipe = $or_map.to_json(map);
              return $json.to_string(_pipe);
            })(),
            snapshot_decoder(),
          );
          return $result.map_error(_pipe, codec_error);
        })(),
        (snapshot) => {
          let _pipe = encode_snapshot(
            new Snapshot(
              $replica_id.to_string(replica),
              snapshot.spec,
              clocks.key_counter,
              snapshot.entries,
            ),
            false,
          );
          let _pipe$1 = $or_map.from_json(_pipe);
          return $result.map_error(_pipe$1, codec_error);
        },
      );
    },
  );
}

export function new_clocks() {
  return new Clocks(0, $dict.new$());
}

/**
 * Import legacy baselines or decode modern snapshots with strict metadata.
 * Legacy deltas are not valid modern replication messages.
 * 
 * @ignore
 */
export function decode_state(encoded) {
  return $result.try$(
    (() => {
      let _pipe = $json.parse(
        encoded,
        $decode.field(
          "v",
          $decode.int,
          (version) => { return $decode.success(version); },
        ),
      );
      return $result.map_error(_pipe, codec_error);
    })(),
    (version) => {
      if (version === 1) {
        return $result.try$(
          read_legacy_map(encoded),
          (metadata) => {
            return $result.try$(
              (() => {
                let _pipe = $json.parse(
                  encoded,
                  $decode.at(toList(["state", "replica_id"]), $decode.string),
                );
                return $result.map_error(_pipe, codec_error);
              })(),
              (author) => {
                let replica = $replica_id.new$(author);
                return $result.try$(
                  (() => {
                    let _pipe = $or_map.import_legacy(
                      encoded,
                      $crdt.CrdtSpec$OrSetSpec$const,
                      $decode.string,
                      replica,
                    );
                    return $result.map_error(_pipe, codec_error);
                  })(),
                  (map) => {
                    return $result.try$(
                      observe_metadata(new_clocks(), metadata),
                      (clocks) => {
                        return retain_counter_floor(map, clocks, replica);
                      },
                    );
                  },
                );
              },
            );
          },
        );
      } else if (version === 2) {
        return $result.try$(
          read_legacy_map(encoded),
          (metadata) => {
            return $result.try$(
              (() => {
                let _pipe = $json.parse(
                  encoded,
                  $decode.at(toList(["state", "replica_id"]), $decode.string),
                );
                return $result.map_error(_pipe, codec_error);
              })(),
              (author) => {
                let replica = $replica_id.new$(author);
                return $result.try$(
                  (() => {
                    let _pipe = $or_map.import_legacy(
                      encoded,
                      $crdt.CrdtSpec$OrSetSpec$const,
                      $decode.string,
                      replica,
                    );
                    return $result.map_error(_pipe, codec_error);
                  })(),
                  (map) => {
                    return $result.try$(
                      observe_metadata(new_clocks(), metadata),
                      (clocks) => {
                        return retain_counter_floor(map, clocks, replica);
                      },
                    );
                  },
                );
              },
            );
          },
        );
      } else {
        return $result.try$(
          read_map(encoded, false),
          (_) => {
            let _pipe = $or_map.from_json(encoded);
            return $result.map_error(_pipe, codec_error);
          },
        );
      }
    },
  );
}

export function decode_delta(encoded) {
  return $result.try$(
    read_map(encoded, true),
    (_) => {
      let _pipe = $or_map.delta_from_json(encoded);
      return $result.map_error(_pipe, codec_error);
    },
  );
}

export function validate_state(map) {
  let _pipe = read_map(
    (() => {
      let _pipe = $or_map.to_json(map);
      return $json.to_string(_pipe);
    })(),
    false,
  );
  return $result.replace(_pipe, undefined);
}

/**
 * Check the declared key and intent without discarding other member history.
 * 
 * @ignore
 */
export function validate_intent(delta, key, intent) {
  return $result.try$(
    read_map(
      (() => {
        let _pipe = $or_map.delta_to_json(delta);
        return $json.to_string(_pipe);
      })(),
      true,
    ),
    (metadata) => {
      let mentioned_keys = metadata.mentioned_keys;
      return $result.try$(
        require(
          $list.all(
            mentioned_keys,
            (mentioned) => { return mentioned === key; },
          ),
          "OR-map delta concerns a different key.",
        ),
        (_) => {
          let empty = ($list.is_empty(mentioned_keys) && $list.is_empty(
            metadata.key_tombstones,
          )) && (metadata.counter === 0);
          if (empty) {
            if (intent instanceof AddMember) {
              return $result.try$(
                (() => {
                  let _pipe = $dict.get(metadata.values, key);
                  return $result.replace_error(
                    _pipe,
                    new InvalidState("OR-map operation has no set value."),
                  );
                })(),
                (leaf) => {
                  if (intent instanceof AddMember) {
                    let member = intent.member;
                    return $result.try$(
                      require(
                        ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                          metadata.key_tombstones,
                        )) && ($dict.size(metadata.bounds) === 0),
                        "Member operation must update only its declared key.",
                      ),
                      (_) => {
                        if (intent instanceof AddMember) {
                          return require(
                            $or_set.contains(leaf.native, member),
                            "Added member is absent from the delta.",
                          );
                        } else if (intent instanceof RemoveMember) {
                          return require(
                            !$or_set.contains(leaf.native, member) && !$list.is_empty(
                              leaf.tombstones,
                            ),
                            "Removed member is live or has no removal history.",
                          );
                        } else {
                          return new Error(
                            new InvalidState("Expected member operation."),
                          );
                        }
                      },
                    );
                  } else if (intent instanceof RemoveMember) {
                    let member = intent.member;
                    return $result.try$(
                      require(
                        ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                          metadata.key_tombstones,
                        )) && ($dict.size(metadata.bounds) === 0),
                        "Member operation must update only its declared key.",
                      ),
                      (_) => {
                        if (intent instanceof AddMember) {
                          return require(
                            $or_set.contains(leaf.native, member),
                            "Added member is absent from the delta.",
                          );
                        } else if (intent instanceof RemoveMember) {
                          return require(
                            !$or_set.contains(leaf.native, member) && !$list.is_empty(
                              leaf.tombstones,
                            ),
                            "Removed member is live or has no removal history.",
                          );
                        } else {
                          return new Error(
                            new InvalidState("Expected member operation."),
                          );
                        }
                      },
                    );
                  } else {
                    return $result.try$(
                      (() => {
                        let _pipe = $dict.get(metadata.bounds, key);
                        return $result.replace_error(
                          _pipe,
                          new InvalidState("Key removal has no removal bound."),
                        );
                      })(),
                      (bound) => {
                        return require(
                          ((($dict.size(metadata.key_entries) === 0) && !$list.is_empty(
                            metadata.key_tombstones,
                          )) && ($dict.size(leaf.entries) === 0)) && $list.all(
                            metadata.key_tombstones,
                            (dot) => {
                              return dot[1] <= $result.unwrap(
                                $dict.get(bound.clocks, dot[0]),
                                0,
                              );
                            },
                          ),
                          "Key removal must clear observed members and bound removed key tags.",
                        );
                      },
                    );
                  }
                },
              );
            } else if (intent instanceof RemoveMember) {
              return new Ok(undefined);
            } else {
              return new Ok(undefined);
            }
          } else if (intent instanceof AddMember) {
            return $result.try$(
              (() => {
                let _pipe = $dict.get(metadata.values, key);
                return $result.replace_error(
                  _pipe,
                  new InvalidState("OR-map operation has no set value."),
                );
              })(),
              (leaf) => {
                if (intent instanceof AddMember) {
                  let member = intent.member;
                  return $result.try$(
                    require(
                      ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                        metadata.key_tombstones,
                      )) && ($dict.size(metadata.bounds) === 0),
                      "Member operation must update only its declared key.",
                    ),
                    (_) => {
                      if (intent instanceof AddMember) {
                        return require(
                          $or_set.contains(leaf.native, member),
                          "Added member is absent from the delta.",
                        );
                      } else if (intent instanceof RemoveMember) {
                        return require(
                          !$or_set.contains(leaf.native, member) && !$list.is_empty(
                            leaf.tombstones,
                          ),
                          "Removed member is live or has no removal history.",
                        );
                      } else {
                        return new Error(
                          new InvalidState("Expected member operation."),
                        );
                      }
                    },
                  );
                } else if (intent instanceof RemoveMember) {
                  let member = intent.member;
                  return $result.try$(
                    require(
                      ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                        metadata.key_tombstones,
                      )) && ($dict.size(metadata.bounds) === 0),
                      "Member operation must update only its declared key.",
                    ),
                    (_) => {
                      if (intent instanceof AddMember) {
                        return require(
                          $or_set.contains(leaf.native, member),
                          "Added member is absent from the delta.",
                        );
                      } else if (intent instanceof RemoveMember) {
                        return require(
                          !$or_set.contains(leaf.native, member) && !$list.is_empty(
                            leaf.tombstones,
                          ),
                          "Removed member is live or has no removal history.",
                        );
                      } else {
                        return new Error(
                          new InvalidState("Expected member operation."),
                        );
                      }
                    },
                  );
                } else {
                  return $result.try$(
                    (() => {
                      let _pipe = $dict.get(metadata.bounds, key);
                      return $result.replace_error(
                        _pipe,
                        new InvalidState("Key removal has no removal bound."),
                      );
                    })(),
                    (bound) => {
                      return require(
                        ((($dict.size(metadata.key_entries) === 0) && !$list.is_empty(
                          metadata.key_tombstones,
                        )) && ($dict.size(leaf.entries) === 0)) && $list.all(
                          metadata.key_tombstones,
                          (dot) => {
                            return dot[1] <= $result.unwrap(
                              $dict.get(bound.clocks, dot[0]),
                              0,
                            );
                          },
                        ),
                        "Key removal must clear observed members and bound removed key tags.",
                      );
                    },
                  );
                }
              },
            );
          } else if (intent instanceof RemoveMember) {
            return $result.try$(
              (() => {
                let _pipe = $dict.get(metadata.values, key);
                return $result.replace_error(
                  _pipe,
                  new InvalidState("OR-map operation has no set value."),
                );
              })(),
              (leaf) => {
                if (intent instanceof AddMember) {
                  let member = intent.member;
                  return $result.try$(
                    require(
                      ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                        metadata.key_tombstones,
                      )) && ($dict.size(metadata.bounds) === 0),
                      "Member operation must update only its declared key.",
                    ),
                    (_) => {
                      if (intent instanceof AddMember) {
                        return require(
                          $or_set.contains(leaf.native, member),
                          "Added member is absent from the delta.",
                        );
                      } else if (intent instanceof RemoveMember) {
                        return require(
                          !$or_set.contains(leaf.native, member) && !$list.is_empty(
                            leaf.tombstones,
                          ),
                          "Removed member is live or has no removal history.",
                        );
                      } else {
                        return new Error(
                          new InvalidState("Expected member operation."),
                        );
                      }
                    },
                  );
                } else if (intent instanceof RemoveMember) {
                  let member = intent.member;
                  return $result.try$(
                    require(
                      ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                        metadata.key_tombstones,
                      )) && ($dict.size(metadata.bounds) === 0),
                      "Member operation must update only its declared key.",
                    ),
                    (_) => {
                      if (intent instanceof AddMember) {
                        return require(
                          $or_set.contains(leaf.native, member),
                          "Added member is absent from the delta.",
                        );
                      } else if (intent instanceof RemoveMember) {
                        return require(
                          !$or_set.contains(leaf.native, member) && !$list.is_empty(
                            leaf.tombstones,
                          ),
                          "Removed member is live or has no removal history.",
                        );
                      } else {
                        return new Error(
                          new InvalidState("Expected member operation."),
                        );
                      }
                    },
                  );
                } else {
                  return $result.try$(
                    (() => {
                      let _pipe = $dict.get(metadata.bounds, key);
                      return $result.replace_error(
                        _pipe,
                        new InvalidState("Key removal has no removal bound."),
                      );
                    })(),
                    (bound) => {
                      return require(
                        ((($dict.size(metadata.key_entries) === 0) && !$list.is_empty(
                          metadata.key_tombstones,
                        )) && ($dict.size(leaf.entries) === 0)) && $list.all(
                          metadata.key_tombstones,
                          (dot) => {
                            return dot[1] <= $result.unwrap(
                              $dict.get(bound.clocks, dot[0]),
                              0,
                            );
                          },
                        ),
                        "Key removal must clear observed members and bound removed key tags.",
                      );
                    },
                  );
                }
              },
            );
          } else {
            return $result.try$(
              (() => {
                let _pipe = $dict.get(metadata.values, key);
                return $result.replace_error(
                  _pipe,
                  new InvalidState("OR-map operation has no set value."),
                );
              })(),
              (leaf) => {
                if (intent instanceof AddMember) {
                  let member = intent.member;
                  return $result.try$(
                    require(
                      ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                        metadata.key_tombstones,
                      )) && ($dict.size(metadata.bounds) === 0),
                      "Member operation must update only its declared key.",
                    ),
                    (_) => {
                      if (intent instanceof AddMember) {
                        return require(
                          $or_set.contains(leaf.native, member),
                          "Added member is absent from the delta.",
                        );
                      } else if (intent instanceof RemoveMember) {
                        return require(
                          !$or_set.contains(leaf.native, member) && !$list.is_empty(
                            leaf.tombstones,
                          ),
                          "Removed member is live or has no removal history.",
                        );
                      } else {
                        return new Error(
                          new InvalidState("Expected member operation."),
                        );
                      }
                    },
                  );
                } else if (intent instanceof RemoveMember) {
                  let member = intent.member;
                  return $result.try$(
                    require(
                      ($dict.has_key(metadata.key_entries, key) && $list.is_empty(
                        metadata.key_tombstones,
                      )) && ($dict.size(metadata.bounds) === 0),
                      "Member operation must update only its declared key.",
                    ),
                    (_) => {
                      if (intent instanceof AddMember) {
                        return require(
                          $or_set.contains(leaf.native, member),
                          "Added member is absent from the delta.",
                        );
                      } else if (intent instanceof RemoveMember) {
                        return require(
                          !$or_set.contains(leaf.native, member) && !$list.is_empty(
                            leaf.tombstones,
                          ),
                          "Removed member is live or has no removal history.",
                        );
                      } else {
                        return new Error(
                          new InvalidState("Expected member operation."),
                        );
                      }
                    },
                  );
                } else {
                  return $result.try$(
                    (() => {
                      let _pipe = $dict.get(metadata.bounds, key);
                      return $result.replace_error(
                        _pipe,
                        new InvalidState("Key removal has no removal bound."),
                      );
                    })(),
                    (bound) => {
                      return require(
                        ((($dict.size(metadata.key_entries) === 0) && !$list.is_empty(
                          metadata.key_tombstones,
                        )) && ($dict.size(leaf.entries) === 0)) && $list.all(
                          metadata.key_tombstones,
                          (dot) => {
                            return dot[1] <= $result.unwrap(
                              $dict.get(bound.clocks, dot[0]),
                              0,
                            );
                          },
                        ),
                        "Key removal must clear observed members and bound removed key tags.",
                      );
                    },
                  );
                }
              },
            );
          }
        },
      );
    },
  );
}

export function observe_delta(clocks, delta) {
  return $result.try$(
    read_map(
      (() => {
        let _pipe = $or_map.delta_to_json(delta);
        return $json.to_string(_pipe);
      })(),
      true,
    ),
    (metadata) => { return observe_metadata(clocks, metadata); },
  );
}

function seed_json(replica, counter) {
  return $json.object(
    toList([
      ["type", $json.string("or_set")],
      ["v", $json.int(2)],
      [
        "state",
        $json.object(
          toList([
            ["replica_id", $json.string($replica_id.to_string(replica))],
            ["counter", $json.int(counter)],
            ["entries", $json.object($List$Empty$const)],
            ["tombstones", $json.array($List$Empty$const, $json.string)],
            ["pruned", $version_vector.to_json($version_vector.new$())],
          ]),
        ),
      ],
    ]),
  );
}

function writable_leaf(metadata, clocks, replica, key) {
  return $result.try$(
    (() => {
      let _pipe = seed_json(replica, clocks.key_counter);
      let _pipe$1 = $json.to_string(_pipe);
      let _pipe$2 = $or_set.from_json(_pipe$1);
      return $result.map_error(_pipe$2, codec_error);
    })(),
    (seed) => {
      let _block;
      let $ = $dict.get(metadata.values, key);
      if ($ instanceof Ok) {
        let retained = $[0];
        _block = $or_set.merge(seed, retained.native);
      } else {
        _block = seed;
      }
      let leaf = _block;
      return new Ok(
        (() => {
          let $1 = $dict.has_key(metadata.key_entries, key);
          if ($1) {
            return leaf;
          } else {
            return $or_set.remove_where(leaf, (_) => { return true; });
          }
        })(),
      );
    },
  );
}

function require_increment(clocks) {
  let $ = clocks.key_counter < safe_counter;
  if ($) {
    return new Ok(undefined);
  } else {
    return new Error(new CounterExhausted("OR-map set counter is exhausted."));
  }
}

function reserve_membership(delta, floor) {
  return $result.try$(
    (() => {
      let _pipe = $json.parse(
        (() => {
          let _pipe = $or_map.delta_to_json(delta);
          return $json.to_string(_pipe);
        })(),
        snapshot_decoder(),
      );
      return $result.map_error(_pipe, codec_error);
    })(),
    (snapshot) => {
      return $result.try$(
        $list.try_map(
          snapshot.entries,
          (entry) => {
            return $result.try$(
              (() => {
                let _pipe = $json.parse(
                  entry.membership,
                  $decode.at(toList(["state", "replica_id"]), $decode.string),
                );
                return $result.map_error(_pipe, codec_error);
              })(),
              (author) => {
                return $result.try$(
                  (() => {
                    let _pipe = seed_json($replica_id.new$(author), floor);
                    let _pipe$1 = $json.to_string(_pipe);
                    let _pipe$2 = $or_set.from_json(_pipe$1);
                    return $result.map_error(_pipe$2, codec_error);
                  })(),
                  (seed) => {
                    let membership = $or_set.add(seed, entry.key);
                    return new Ok(
                      new Entry(
                        entry.key,
                        entry.generation,
                        (() => {
                          let _pipe = $or_set.to_json_with(
                            membership,
                            $json.string,
                          );
                          return $json.to_string(_pipe);
                        })(),
                        entry.value,
                      ),
                    );
                  },
                );
              },
            );
          },
        ),
        (entries) => {
          let _pipe = encode_snapshot(
            new Snapshot(snapshot.author, snapshot.spec, floor + 1, entries),
            true,
          );
          let _pipe$1 = $or_map.delta_from_json(_pipe);
          return $result.map_error(_pipe$1, codec_error);
        },
      );
    },
  );
}

function update_leaf(working, clocks, key, leaf) {
  return $result.try$(
    (() => {
      let _pipe = $or_map.update_with_delta(
        working,
        key,
        (_) => { return new $crdt.CrdtOrSet(leaf); },
      );
      return $result.map_error(_pipe, merge_error);
    })(),
    (_use0) => {
      let delta = _use0[1];
      return $result.try$(
        reserve_membership(delta, clocks.key_counter),
        (delta) => {
          return $result.try$(
            observe_delta(clocks, delta),
            (clocks) => { return new Ok([delta, clocks]); },
          );
        },
      );
    },
  );
}

export function add(map, clocks, replica, key, member) {
  return $result.try$(
    read_map(
      (() => {
        let _pipe = $or_map.to_json(map);
        return $json.to_string(_pipe);
      })(),
      false,
    ),
    (metadata) => {
      return $result.try$(
        observe_metadata(clocks, metadata),
        (clocks) => {
          return $result.try$(
            require_increment(clocks),
            (_) => {
              return $result.try$(
                retain_counter_floor(map, clocks, replica),
                (working) => {
                  return $result.try$(
                    writable_leaf(metadata, clocks, replica, key),
                    (leaf) => {
                      return update_leaf(
                        working,
                        clocks,
                        key,
                        $or_set.add(leaf, member),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
    },
  );
}

export function remove_member(map, clocks, replica, key, member) {
  return $result.try$(
    read_map(
      (() => {
        let _pipe = $or_map.to_json(map);
        return $json.to_string(_pipe);
      })(),
      false,
    ),
    (metadata) => {
      return $result.try$(
        observe_metadata(clocks, metadata),
        (observed) => {
          let _block;
          let $ = $dict.get(metadata.values, key);
          if ($ instanceof Ok) {
            let leaf = $[0];
            _block = $dict.has_key(metadata.key_entries, key) && $or_set.contains(
              leaf.native,
              member,
            );
          } else {
            _block = false;
          }
          let present = _block;
          if (present) {
            return $result.try$(
              require_increment(observed),
              (_) => {
                return $result.try$(
                  retain_counter_floor(map, observed, replica),
                  (working) => {
                    return $result.try$(
                      writable_leaf(metadata, observed, replica, key),
                      (leaf) => {
                        return update_leaf(
                          working,
                          observed,
                          key,
                          $or_set.remove(leaf, member),
                        );
                      },
                    );
                  },
                );
              },
            );
          } else {
            return new Ok([$or_map.empty_delta(map), clocks]);
          }
        },
      );
    },
  );
}

export function remove_key(map, clocks, replica, key) {
  return $result.try$(
    read_map(
      (() => {
        let _pipe = $or_map.to_json(map);
        return $json.to_string(_pipe);
      })(),
      false,
    ),
    (metadata) => {
      return $result.try$(
        observe_metadata(clocks, metadata),
        (observed) => {
          let $ = $dict.has_key(metadata.key_entries, key);
          if ($) {
            return $result.try$(
              require_increment(observed),
              (_) => {
                return $result.try$(
                  retain_counter_floor(map, observed, replica),
                  (working) => {
                    return $result.try$(
                      writable_leaf(metadata, observed, replica, key),
                      (leaf) => {
                        let cleared = $or_set.remove_where(
                          leaf,
                          (_) => { return true; },
                        );
                        return $result.try$(
                          (() => {
                            let _pipe = $or_map.update_with_delta(
                              working,
                              key,
                              (_) => { return new $crdt.CrdtOrSet(cleared); },
                            );
                            return $result.map_error(_pipe, merge_error);
                          })(),
                          (_use0) => {
                            let clear_delta = _use0[1];
                            return $result.try$(
                              reserve_membership(
                                clear_delta,
                                observed.key_counter,
                              ),
                              (clear_delta) => {
                                return $result.try$(
                                  apply_delta(working, clear_delta),
                                  (cleared_map) => {
                                    let $1 = $or_map.remove_with_delta(
                                      cleared_map,
                                      key,
                                    );
                                    let key_delta = $1[1];
                                    return $result.try$(
                                      (() => {
                                        let _pipe = $or_map.merge_deltas(
                                          clear_delta,
                                          key_delta,
                                        );
                                        return $result.map_error(
                                          _pipe,
                                          merge_error,
                                        );
                                      })(),
                                      (delta) => {
                                        return $result.try$(
                                          observe_delta(observed, delta),
                                          (clocks) => {
                                            return new Ok([delta, clocks]);
                                          },
                                        );
                                      },
                                    );
                                  },
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            );
          } else {
            return new Ok([$or_map.empty_delta(map), clocks]);
          }
        },
      );
    },
  );
}
