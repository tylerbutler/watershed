/// <reference types="./channel.d.mts" />
import * as $json from "../../gleam_json/gleam/json.mjs";
import * as $decode from "../../gleam_stdlib/gleam/dynamic/decode.mjs";
import * as $int from "../../gleam_stdlib/gleam/int.mjs";
import * as $list from "../../gleam_stdlib/gleam/list.mjs";
import * as $option from "../../gleam_stdlib/gleam/option.mjs";
import { Some, Option$None$const } from "../../gleam_stdlib/gleam/option.mjs";
import * as $result from "../../gleam_stdlib/gleam/result.mjs";
import * as $replica_id from "../../lattice_core/lattice_core/replica_id.mjs";
import * as $g_counter from "../../lattice_counters/lattice_counters/g_counter.mjs";
import * as $pn_counter from "../../lattice_counters/lattice_counters/pn_counter.mjs";
import * as $lww_map from "../../lattice_maps/lattice_maps/lww_map.mjs";
import * as $or_map from "../../lattice_maps/lattice_maps/or_map.mjs";
import * as $lww_register from "../../lattice_registers/lattice_registers/lww_register.mjs";
import * as $mv_register from "../../lattice_registers/lattice_registers/mv_register.mjs";
import * as $sequence from "../../lattice_sequence/lattice_sequence/sequence.mjs";
import * as $g_set from "../../lattice_sets/lattice_sets/g_set.mjs";
import * as $or_set from "../../lattice_sets/lattice_sets/or_set.mjs";
import * as $two_p_set from "../../lattice_sets/lattice_sets/two_p_set.mjs";
import * as $text from "../../lattice_text/lattice_text/text.mjs";
import {
  Ok,
  Error,
  toList,
  Empty as $Empty,
  List$Empty$const as $List$Empty$const,
  prepend as listPrepend,
  CustomType as $CustomType,
  isEqual,
} from "../gleam.mjs";
import * as $claims_kernel from "../watershed/claims_kernel.mjs";
import * as $counter_kernel from "../watershed/counter_kernel.mjs";
import * as $directory_kernel from "../watershed/directory_kernel.mjs";
import * as $g_counter_kernel from "../watershed/g_counter_kernel.mjs";
import * as $g_set_kernel from "../watershed/g_set_kernel.mjs";
import * as $handle from "../watershed/handle.mjs";
import * as $json_ot from "../watershed/json_ot.mjs";
import * as $json_ot_kernel from "../watershed/json_ot_kernel.mjs";
import * as $lww_clock from "../watershed/lww_clock.mjs";
import * as $lww_map_kernel from "../watershed/lww_map_kernel.mjs";
import * as $lww_register_kernel from "../watershed/lww_register_kernel.mjs";
import * as $map_kernel from "../watershed/map_kernel.mjs";
import * as $mv_register_kernel from "../watershed/mv_register_kernel.mjs";
import * as $or_map_kernel from "../watershed/or_map_kernel.mjs";
import * as $or_set_kernel from "../watershed/or_set_kernel.mjs";
import * as $ordered_collection_kernel from "../watershed/ordered_collection_kernel.mjs";
import * as $pact_map_kernel from "../watershed/pact_map_kernel.mjs";
import * as $pn_counter_kernel from "../watershed/pn_counter_kernel.mjs";
import * as $register_collection_kernel from "../watershed/register_collection_kernel.mjs";
import * as $rich_text from "../watershed/rich_text.mjs";
import * as $rich_text_kernel from "../watershed/rich_text_kernel.mjs";
import * as $sequence_kernel from "../watershed/sequence_kernel.mjs";
import * as $task_manager_kernel from "../watershed/task_manager_kernel.mjs";
import * as $text_kernel from "../watershed/text_kernel.mjs";
import * as $two_p_set_kernel from "../watershed/two_p_set_kernel.mjs";
import * as $wire from "../watershed/wire.mjs";

export class MapChannel extends $CustomType {}
export const ChannelType$MapChannel$const = new MapChannel();
export const ChannelType$MapChannel = () => ChannelType$MapChannel$const;
export const ChannelType$isMapChannel = (value) => value instanceof MapChannel;

export class CounterChannel extends $CustomType {}
export const ChannelType$CounterChannel$const = new CounterChannel();
export const ChannelType$CounterChannel = () =>
  ChannelType$CounterChannel$const;
export const ChannelType$isCounterChannel = (value) =>
  value instanceof CounterChannel;

export class PnCounterChannel extends $CustomType {}
export const ChannelType$PnCounterChannel$const = new PnCounterChannel();
export const ChannelType$PnCounterChannel = () =>
  ChannelType$PnCounterChannel$const;
export const ChannelType$isPnCounterChannel = (value) =>
  value instanceof PnCounterChannel;

export class GCounterChannel extends $CustomType {}
export const ChannelType$GCounterChannel$const = new GCounterChannel();
export const ChannelType$GCounterChannel = () =>
  ChannelType$GCounterChannel$const;
export const ChannelType$isGCounterChannel = (value) =>
  value instanceof GCounterChannel;

export class LwwRegisterChannel extends $CustomType {}
export const ChannelType$LwwRegisterChannel$const = new LwwRegisterChannel();
export const ChannelType$LwwRegisterChannel = () =>
  ChannelType$LwwRegisterChannel$const;
export const ChannelType$isLwwRegisterChannel = (value) =>
  value instanceof LwwRegisterChannel;

export class LwwMapChannel extends $CustomType {}
export const ChannelType$LwwMapChannel$const = new LwwMapChannel();
export const ChannelType$LwwMapChannel = () => ChannelType$LwwMapChannel$const;
export const ChannelType$isLwwMapChannel = (value) =>
  value instanceof LwwMapChannel;

export class MvRegisterChannel extends $CustomType {}
export const ChannelType$MvRegisterChannel$const = new MvRegisterChannel();
export const ChannelType$MvRegisterChannel = () =>
  ChannelType$MvRegisterChannel$const;
export const ChannelType$isMvRegisterChannel = (value) =>
  value instanceof MvRegisterChannel;

export class OrMapChannel extends $CustomType {}
export const ChannelType$OrMapChannel$const = new OrMapChannel();
export const ChannelType$OrMapChannel = () => ChannelType$OrMapChannel$const;
export const ChannelType$isOrMapChannel = (value) =>
  value instanceof OrMapChannel;

export class OrSetChannel extends $CustomType {}
export const ChannelType$OrSetChannel$const = new OrSetChannel();
export const ChannelType$OrSetChannel = () => ChannelType$OrSetChannel$const;
export const ChannelType$isOrSetChannel = (value) =>
  value instanceof OrSetChannel;

export class GSetChannel extends $CustomType {}
export const ChannelType$GSetChannel$const = new GSetChannel();
export const ChannelType$GSetChannel = () => ChannelType$GSetChannel$const;
export const ChannelType$isGSetChannel = (value) =>
  value instanceof GSetChannel;

export class TwoPSetChannel extends $CustomType {}
export const ChannelType$TwoPSetChannel$const = new TwoPSetChannel();
export const ChannelType$TwoPSetChannel = () =>
  ChannelType$TwoPSetChannel$const;
export const ChannelType$isTwoPSetChannel = (value) =>
  value instanceof TwoPSetChannel;

export class RegisterCollectionChannel extends $CustomType {}
export const ChannelType$RegisterCollectionChannel$const =
  new RegisterCollectionChannel();
export const ChannelType$RegisterCollectionChannel = () =>
  ChannelType$RegisterCollectionChannel$const;
export const ChannelType$isRegisterCollectionChannel = (value) =>
  value instanceof RegisterCollectionChannel;

export class ClaimsChannel extends $CustomType {}
export const ChannelType$ClaimsChannel$const = new ClaimsChannel();
export const ChannelType$ClaimsChannel = () => ChannelType$ClaimsChannel$const;
export const ChannelType$isClaimsChannel = (value) =>
  value instanceof ClaimsChannel;

export class TaskManagerChannel extends $CustomType {}
export const ChannelType$TaskManagerChannel$const = new TaskManagerChannel();
export const ChannelType$TaskManagerChannel = () =>
  ChannelType$TaskManagerChannel$const;
export const ChannelType$isTaskManagerChannel = (value) =>
  value instanceof TaskManagerChannel;

export class PactMapChannel extends $CustomType {}
export const ChannelType$PactMapChannel$const = new PactMapChannel();
export const ChannelType$PactMapChannel = () =>
  ChannelType$PactMapChannel$const;
export const ChannelType$isPactMapChannel = (value) =>
  value instanceof PactMapChannel;

export class JsonOtChannel extends $CustomType {}
export const ChannelType$JsonOtChannel$const = new JsonOtChannel();
export const ChannelType$JsonOtChannel = () => ChannelType$JsonOtChannel$const;
export const ChannelType$isJsonOtChannel = (value) =>
  value instanceof JsonOtChannel;

export class DirectoryChannel extends $CustomType {}
export const ChannelType$DirectoryChannel$const = new DirectoryChannel();
export const ChannelType$DirectoryChannel = () =>
  ChannelType$DirectoryChannel$const;
export const ChannelType$isDirectoryChannel = (value) =>
  value instanceof DirectoryChannel;

export class OrderedCollectionChannel extends $CustomType {}
export const ChannelType$OrderedCollectionChannel$const =
  new OrderedCollectionChannel();
export const ChannelType$OrderedCollectionChannel = () =>
  ChannelType$OrderedCollectionChannel$const;
export const ChannelType$isOrderedCollectionChannel = (value) =>
  value instanceof OrderedCollectionChannel;

export class SequenceChannel extends $CustomType {}
export const ChannelType$SequenceChannel$const = new SequenceChannel();
export const ChannelType$SequenceChannel = () =>
  ChannelType$SequenceChannel$const;
export const ChannelType$isSequenceChannel = (value) =>
  value instanceof SequenceChannel;

export class RichTextChannel extends $CustomType {}
export const ChannelType$RichTextChannel$const = new RichTextChannel();
export const ChannelType$RichTextChannel = () =>
  ChannelType$RichTextChannel$const;
export const ChannelType$isRichTextChannel = (value) =>
  value instanceof RichTextChannel;

export class TextChannel extends $CustomType {}
export const ChannelType$TextChannel$const = new TextChannel();
export const ChannelType$TextChannel = () => ChannelType$TextChannel$const;
export const ChannelType$isTextChannel = (value) =>
  value instanceof TextChannel;

export class InitMap extends $CustomType {}
export const ChannelInit$InitMap$const = new InitMap();
export const ChannelInit$InitMap = () => ChannelInit$InitMap$const;
export const ChannelInit$isInitMap = (value) => value instanceof InitMap;

export class InitCounter extends $CustomType {}
export const ChannelInit$InitCounter$const = new InitCounter();
export const ChannelInit$InitCounter = () => ChannelInit$InitCounter$const;
export const ChannelInit$isInitCounter = (value) =>
  value instanceof InitCounter;

export class InitPnCounter extends $CustomType {}
export const ChannelInit$InitPnCounter$const = new InitPnCounter();
export const ChannelInit$InitPnCounter = () => ChannelInit$InitPnCounter$const;
export const ChannelInit$isInitPnCounter = (value) =>
  value instanceof InitPnCounter;

export class InitGCounter extends $CustomType {}
export const ChannelInit$InitGCounter$const = new InitGCounter();
export const ChannelInit$InitGCounter = () => ChannelInit$InitGCounter$const;
export const ChannelInit$isInitGCounter = (value) =>
  value instanceof InitGCounter;

export class InitLwwRegister extends $CustomType {}
export const ChannelInit$InitLwwRegister$const = new InitLwwRegister();
export const ChannelInit$InitLwwRegister = () =>
  ChannelInit$InitLwwRegister$const;
export const ChannelInit$isInitLwwRegister = (value) =>
  value instanceof InitLwwRegister;

export class InitLwwMap extends $CustomType {}
export const ChannelInit$InitLwwMap$const = new InitLwwMap();
export const ChannelInit$InitLwwMap = () => ChannelInit$InitLwwMap$const;
export const ChannelInit$isInitLwwMap = (value) => value instanceof InitLwwMap;

export class InitMvRegister extends $CustomType {}
export const ChannelInit$InitMvRegister$const = new InitMvRegister();
export const ChannelInit$InitMvRegister = () =>
  ChannelInit$InitMvRegister$const;
export const ChannelInit$isInitMvRegister = (value) =>
  value instanceof InitMvRegister;

export class InitOrMap extends $CustomType {
  constructor(mode) {
    super();
    this.mode = mode;
  }
}
export const ChannelInit$InitOrMap = (mode) => new InitOrMap(mode);
export const ChannelInit$isInitOrMap = (value) => value instanceof InitOrMap;
export const ChannelInit$InitOrMap$mode = (value) => value.mode;
export const ChannelInit$InitOrMap$0 = (value) => value.mode;

export class InitOrSet extends $CustomType {}
export const ChannelInit$InitOrSet$const = new InitOrSet();
export const ChannelInit$InitOrSet = () => ChannelInit$InitOrSet$const;
export const ChannelInit$isInitOrSet = (value) => value instanceof InitOrSet;

export class InitGSet extends $CustomType {}
export const ChannelInit$InitGSet$const = new InitGSet();
export const ChannelInit$InitGSet = () => ChannelInit$InitGSet$const;
export const ChannelInit$isInitGSet = (value) => value instanceof InitGSet;

export class InitTwoPSet extends $CustomType {}
export const ChannelInit$InitTwoPSet$const = new InitTwoPSet();
export const ChannelInit$InitTwoPSet = () => ChannelInit$InitTwoPSet$const;
export const ChannelInit$isInitTwoPSet = (value) =>
  value instanceof InitTwoPSet;

export class InitRegisterCollection extends $CustomType {}
export const ChannelInit$InitRegisterCollection$const =
  new InitRegisterCollection();
export const ChannelInit$InitRegisterCollection = () =>
  ChannelInit$InitRegisterCollection$const;
export const ChannelInit$isInitRegisterCollection = (value) =>
  value instanceof InitRegisterCollection;

export class InitClaims extends $CustomType {}
export const ChannelInit$InitClaims$const = new InitClaims();
export const ChannelInit$InitClaims = () => ChannelInit$InitClaims$const;
export const ChannelInit$isInitClaims = (value) => value instanceof InitClaims;

export class InitTaskManager extends $CustomType {}
export const ChannelInit$InitTaskManager$const = new InitTaskManager();
export const ChannelInit$InitTaskManager = () =>
  ChannelInit$InitTaskManager$const;
export const ChannelInit$isInitTaskManager = (value) =>
  value instanceof InitTaskManager;

export class InitPactMap extends $CustomType {}
export const ChannelInit$InitPactMap$const = new InitPactMap();
export const ChannelInit$InitPactMap = () => ChannelInit$InitPactMap$const;
export const ChannelInit$isInitPactMap = (value) =>
  value instanceof InitPactMap;

export class InitJsonOt extends $CustomType {}
export const ChannelInit$InitJsonOt$const = new InitJsonOt();
export const ChannelInit$InitJsonOt = () => ChannelInit$InitJsonOt$const;
export const ChannelInit$isInitJsonOt = (value) => value instanceof InitJsonOt;

export class InitDirectory extends $CustomType {}
export const ChannelInit$InitDirectory$const = new InitDirectory();
export const ChannelInit$InitDirectory = () => ChannelInit$InitDirectory$const;
export const ChannelInit$isInitDirectory = (value) =>
  value instanceof InitDirectory;

export class InitOrderedCollection extends $CustomType {}
export const ChannelInit$InitOrderedCollection$const =
  new InitOrderedCollection();
export const ChannelInit$InitOrderedCollection = () =>
  ChannelInit$InitOrderedCollection$const;
export const ChannelInit$isInitOrderedCollection = (value) =>
  value instanceof InitOrderedCollection;

export class InitSequence extends $CustomType {}
export const ChannelInit$InitSequence$const = new InitSequence();
export const ChannelInit$InitSequence = () => ChannelInit$InitSequence$const;
export const ChannelInit$isInitSequence = (value) =>
  value instanceof InitSequence;

export class InitRichText extends $CustomType {}
export const ChannelInit$InitRichText$const = new InitRichText();
export const ChannelInit$InitRichText = () => ChannelInit$InitRichText$const;
export const ChannelInit$isInitRichText = (value) =>
  value instanceof InitRichText;

export class InitText extends $CustomType {}
export const ChannelInit$InitText$const = new InitText();
export const ChannelInit$InitText = () => ChannelInit$InitText$const;
export const ChannelInit$isInitText = (value) => value instanceof InitText;

export class MapState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$MapState = ($0) => new MapState($0);
export const ChannelState$isMapState = (value) => value instanceof MapState;
export const ChannelState$MapState$0 = (value) => value[0];

export class CounterState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$CounterState = ($0) => new CounterState($0);
export const ChannelState$isCounterState = (value) =>
  value instanceof CounterState;
export const ChannelState$CounterState$0 = (value) => value[0];

export class PnCounterState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$PnCounterState = ($0) => new PnCounterState($0);
export const ChannelState$isPnCounterState = (value) =>
  value instanceof PnCounterState;
export const ChannelState$PnCounterState$0 = (value) => value[0];

export class GCounterState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$GCounterState = ($0) => new GCounterState($0);
export const ChannelState$isGCounterState = (value) =>
  value instanceof GCounterState;
export const ChannelState$GCounterState$0 = (value) => value[0];

export class LwwRegisterState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$LwwRegisterState = ($0) => new LwwRegisterState($0);
export const ChannelState$isLwwRegisterState = (value) =>
  value instanceof LwwRegisterState;
export const ChannelState$LwwRegisterState$0 = (value) => value[0];

export class LwwMapState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$LwwMapState = ($0) => new LwwMapState($0);
export const ChannelState$isLwwMapState = (value) =>
  value instanceof LwwMapState;
export const ChannelState$LwwMapState$0 = (value) => value[0];

export class MvRegisterState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$MvRegisterState = ($0) => new MvRegisterState($0);
export const ChannelState$isMvRegisterState = (value) =>
  value instanceof MvRegisterState;
export const ChannelState$MvRegisterState$0 = (value) => value[0];

export class OrMapState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$OrMapState = ($0) => new OrMapState($0);
export const ChannelState$isOrMapState = (value) => value instanceof OrMapState;
export const ChannelState$OrMapState$0 = (value) => value[0];

export class OrSetState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$OrSetState = ($0) => new OrSetState($0);
export const ChannelState$isOrSetState = (value) => value instanceof OrSetState;
export const ChannelState$OrSetState$0 = (value) => value[0];

export class GSetState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$GSetState = ($0) => new GSetState($0);
export const ChannelState$isGSetState = (value) => value instanceof GSetState;
export const ChannelState$GSetState$0 = (value) => value[0];

export class TwoPSetState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$TwoPSetState = ($0) => new TwoPSetState($0);
export const ChannelState$isTwoPSetState = (value) =>
  value instanceof TwoPSetState;
export const ChannelState$TwoPSetState$0 = (value) => value[0];

export class RegisterCollectionState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$RegisterCollectionState = ($0) =>
  new RegisterCollectionState($0);
export const ChannelState$isRegisterCollectionState = (value) =>
  value instanceof RegisterCollectionState;
export const ChannelState$RegisterCollectionState$0 = (value) => value[0];

export class ClaimsState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$ClaimsState = ($0) => new ClaimsState($0);
export const ChannelState$isClaimsState = (value) =>
  value instanceof ClaimsState;
export const ChannelState$ClaimsState$0 = (value) => value[0];

export class TaskManagerState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$TaskManagerState = ($0) => new TaskManagerState($0);
export const ChannelState$isTaskManagerState = (value) =>
  value instanceof TaskManagerState;
export const ChannelState$TaskManagerState$0 = (value) => value[0];

export class PactMapState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$PactMapState = ($0) => new PactMapState($0);
export const ChannelState$isPactMapState = (value) =>
  value instanceof PactMapState;
export const ChannelState$PactMapState$0 = (value) => value[0];

export class JsonOtState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$JsonOtState = ($0) => new JsonOtState($0);
export const ChannelState$isJsonOtState = (value) =>
  value instanceof JsonOtState;
export const ChannelState$JsonOtState$0 = (value) => value[0];

export class DirectoryState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$DirectoryState = ($0) => new DirectoryState($0);
export const ChannelState$isDirectoryState = (value) =>
  value instanceof DirectoryState;
export const ChannelState$DirectoryState$0 = (value) => value[0];

export class OrderedCollectionState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$OrderedCollectionState = ($0) =>
  new OrderedCollectionState($0);
export const ChannelState$isOrderedCollectionState = (value) =>
  value instanceof OrderedCollectionState;
export const ChannelState$OrderedCollectionState$0 = (value) => value[0];

export class SequenceState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$SequenceState = ($0) => new SequenceState($0);
export const ChannelState$isSequenceState = (value) =>
  value instanceof SequenceState;
export const ChannelState$SequenceState$0 = (value) => value[0];

export class RichTextState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$RichTextState = ($0) => new RichTextState($0);
export const ChannelState$isRichTextState = (value) =>
  value instanceof RichTextState;
export const ChannelState$RichTextState$0 = (value) => value[0];

export class TextState extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelState$TextState = ($0) => new TextState($0);
export const ChannelState$isTextState = (value) => value instanceof TextState;
export const ChannelState$TextState$0 = (value) => value[0];

export class MapOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$MapOperation = ($0) => new MapOperation($0);
export const ChannelOperation$isMapOperation = (value) =>
  value instanceof MapOperation;
export const ChannelOperation$MapOperation$0 = (value) => value[0];

export class CounterOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$CounterOperation = ($0) =>
  new CounterOperation($0);
export const ChannelOperation$isCounterOperation = (value) =>
  value instanceof CounterOperation;
export const ChannelOperation$CounterOperation$0 = (value) => value[0];

export class PnCounterOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$PnCounterOperation = ($0) =>
  new PnCounterOperation($0);
export const ChannelOperation$isPnCounterOperation = (value) =>
  value instanceof PnCounterOperation;
export const ChannelOperation$PnCounterOperation$0 = (value) => value[0];

export class GCounterOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$GCounterOperation = ($0) =>
  new GCounterOperation($0);
export const ChannelOperation$isGCounterOperation = (value) =>
  value instanceof GCounterOperation;
export const ChannelOperation$GCounterOperation$0 = (value) => value[0];

export class LwwRegisterOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$LwwRegisterOperation = ($0) =>
  new LwwRegisterOperation($0);
export const ChannelOperation$isLwwRegisterOperation = (value) =>
  value instanceof LwwRegisterOperation;
export const ChannelOperation$LwwRegisterOperation$0 = (value) => value[0];

export class LwwMapOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$LwwMapOperation = ($0) => new LwwMapOperation($0);
export const ChannelOperation$isLwwMapOperation = (value) =>
  value instanceof LwwMapOperation;
export const ChannelOperation$LwwMapOperation$0 = (value) => value[0];

export class MvRegisterOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$MvRegisterOperation = ($0) =>
  new MvRegisterOperation($0);
export const ChannelOperation$isMvRegisterOperation = (value) =>
  value instanceof MvRegisterOperation;
export const ChannelOperation$MvRegisterOperation$0 = (value) => value[0];

export class OrMapOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$OrMapOperation = ($0) => new OrMapOperation($0);
export const ChannelOperation$isOrMapOperation = (value) =>
  value instanceof OrMapOperation;
export const ChannelOperation$OrMapOperation$0 = (value) => value[0];

export class OrSetOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$OrSetOperation = ($0) => new OrSetOperation($0);
export const ChannelOperation$isOrSetOperation = (value) =>
  value instanceof OrSetOperation;
export const ChannelOperation$OrSetOperation$0 = (value) => value[0];

export class GSetOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$GSetOperation = ($0) => new GSetOperation($0);
export const ChannelOperation$isGSetOperation = (value) =>
  value instanceof GSetOperation;
export const ChannelOperation$GSetOperation$0 = (value) => value[0];

export class TwoPSetOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$TwoPSetOperation = ($0) =>
  new TwoPSetOperation($0);
export const ChannelOperation$isTwoPSetOperation = (value) =>
  value instanceof TwoPSetOperation;
export const ChannelOperation$TwoPSetOperation$0 = (value) => value[0];

export class RegisterCollectionOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$RegisterCollectionOperation = ($0) =>
  new RegisterCollectionOperation($0);
export const ChannelOperation$isRegisterCollectionOperation = (value) =>
  value instanceof RegisterCollectionOperation;
export const ChannelOperation$RegisterCollectionOperation$0 = (value) =>
  value[0];

export class ClaimsOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$ClaimsOperation = ($0) => new ClaimsOperation($0);
export const ChannelOperation$isClaimsOperation = (value) =>
  value instanceof ClaimsOperation;
export const ChannelOperation$ClaimsOperation$0 = (value) => value[0];

export class TaskManagerOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$TaskManagerOperation = ($0) =>
  new TaskManagerOperation($0);
export const ChannelOperation$isTaskManagerOperation = (value) =>
  value instanceof TaskManagerOperation;
export const ChannelOperation$TaskManagerOperation$0 = (value) => value[0];

export class PactMapOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$PactMapOperation = ($0) =>
  new PactMapOperation($0);
export const ChannelOperation$isPactMapOperation = (value) =>
  value instanceof PactMapOperation;
export const ChannelOperation$PactMapOperation$0 = (value) => value[0];

export class JsonOtOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$JsonOtOperation = ($0) => new JsonOtOperation($0);
export const ChannelOperation$isJsonOtOperation = (value) =>
  value instanceof JsonOtOperation;
export const ChannelOperation$JsonOtOperation$0 = (value) => value[0];

/**
 * A directory operation with the kernel `message_id` value that identifies
 * this submission. Unlike the other kernels, the id travels *in the
 * operation*. A remote client needs the client-sequence identity of the
 * author to run the stale-instance filter (D12) and the sibling order (D9).
 * The client_sequence_number of the runtime counts the operations of every
 * channel together, and it would thus not equal the counter that the kernel
 * keeps for each directory.
 */
export class DirectoryOperation extends $CustomType {
  constructor(operation, message_id) {
    super();
    this.operation = operation;
    this.message_id = message_id;
  }
}
export const ChannelOperation$DirectoryOperation = (operation, message_id) =>
  new DirectoryOperation(operation, message_id);
export const ChannelOperation$isDirectoryOperation = (value) =>
  value instanceof DirectoryOperation;
export const ChannelOperation$DirectoryOperation$operation = (value) =>
  value.operation;
export const ChannelOperation$DirectoryOperation$0 = (value) => value.operation;
export const ChannelOperation$DirectoryOperation$message_id = (value) =>
  value.message_id;
export const ChannelOperation$DirectoryOperation$1 = (value) =>
  value.message_id;

export class OrderedCollectionOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$OrderedCollectionOperation = ($0) =>
  new OrderedCollectionOperation($0);
export const ChannelOperation$isOrderedCollectionOperation = (value) =>
  value instanceof OrderedCollectionOperation;
export const ChannelOperation$OrderedCollectionOperation$0 = (value) =>
  value[0];

export class SequenceOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$SequenceOperation = ($0) =>
  new SequenceOperation($0);
export const ChannelOperation$isSequenceOperation = (value) =>
  value instanceof SequenceOperation;
export const ChannelOperation$SequenceOperation$0 = (value) => value[0];

export class RichTextOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$RichTextOperation = ($0) =>
  new RichTextOperation($0);
export const ChannelOperation$isRichTextOperation = (value) =>
  value instanceof RichTextOperation;
export const ChannelOperation$RichTextOperation$0 = (value) => value[0];

export class TextOperation extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelOperation$TextOperation = ($0) => new TextOperation($0);
export const ChannelOperation$isTextOperation = (value) =>
  value instanceof TextOperation;
export const ChannelOperation$TextOperation$0 = (value) => value[0];

export class PnCounterEdit extends $CustomType {
  constructor(amount) {
    super();
    this.amount = amount;
  }
}
export const P2pEdit$PnCounterEdit = (amount) => new PnCounterEdit(amount);
export const P2pEdit$isPnCounterEdit = (value) =>
  value instanceof PnCounterEdit;
export const P2pEdit$PnCounterEdit$amount = (value) => value.amount;
export const P2pEdit$PnCounterEdit$0 = (value) => value.amount;

export class GCounterIncrementEdit extends $CustomType {
  constructor(amount) {
    super();
    this.amount = amount;
  }
}
export const P2pEdit$GCounterIncrementEdit = (amount) =>
  new GCounterIncrementEdit(amount);
export const P2pEdit$isGCounterIncrementEdit = (value) =>
  value instanceof GCounterIncrementEdit;
export const P2pEdit$GCounterIncrementEdit$amount = (value) => value.amount;
export const P2pEdit$GCounterIncrementEdit$0 = (value) => value.amount;

export class LwwRegisterSetEdit extends $CustomType {
  constructor(value, timestamp) {
    super();
    this.value = value;
    this.timestamp = timestamp;
  }
}
export const P2pEdit$LwwRegisterSetEdit = (value, timestamp) =>
  new LwwRegisterSetEdit(value, timestamp);
export const P2pEdit$isLwwRegisterSetEdit = (value) =>
  value instanceof LwwRegisterSetEdit;
export const P2pEdit$LwwRegisterSetEdit$value = (value) => value.value;
export const P2pEdit$LwwRegisterSetEdit$0 = (value) => value.value;
export const P2pEdit$LwwRegisterSetEdit$timestamp = (value) => value.timestamp;
export const P2pEdit$LwwRegisterSetEdit$1 = (value) => value.timestamp;

export class LwwMapSetEdit extends $CustomType {
  constructor(key, value, timestamp) {
    super();
    this.key = key;
    this.value = value;
    this.timestamp = timestamp;
  }
}
export const P2pEdit$LwwMapSetEdit = (key, value, timestamp) =>
  new LwwMapSetEdit(key, value, timestamp);
export const P2pEdit$isLwwMapSetEdit = (value) =>
  value instanceof LwwMapSetEdit;
export const P2pEdit$LwwMapSetEdit$key = (value) => value.key;
export const P2pEdit$LwwMapSetEdit$0 = (value) => value.key;
export const P2pEdit$LwwMapSetEdit$value = (value) => value.value;
export const P2pEdit$LwwMapSetEdit$1 = (value) => value.value;
export const P2pEdit$LwwMapSetEdit$timestamp = (value) => value.timestamp;
export const P2pEdit$LwwMapSetEdit$2 = (value) => value.timestamp;

export class LwwMapRemoveEdit extends $CustomType {
  constructor(key, timestamp) {
    super();
    this.key = key;
    this.timestamp = timestamp;
  }
}
export const P2pEdit$LwwMapRemoveEdit = (key, timestamp) =>
  new LwwMapRemoveEdit(key, timestamp);
export const P2pEdit$isLwwMapRemoveEdit = (value) =>
  value instanceof LwwMapRemoveEdit;
export const P2pEdit$LwwMapRemoveEdit$key = (value) => value.key;
export const P2pEdit$LwwMapRemoveEdit$0 = (value) => value.key;
export const P2pEdit$LwwMapRemoveEdit$timestamp = (value) => value.timestamp;
export const P2pEdit$LwwMapRemoveEdit$1 = (value) => value.timestamp;

export class MvRegisterEdit extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
export const P2pEdit$MvRegisterEdit = (value) => new MvRegisterEdit(value);
export const P2pEdit$isMvRegisterEdit = (value) =>
  value instanceof MvRegisterEdit;
export const P2pEdit$MvRegisterEdit$value = (value) => value.value;
export const P2pEdit$MvRegisterEdit$0 = (value) => value.value;

export class OrMapIncrementEdit extends $CustomType {
  constructor(key, amount) {
    super();
    this.key = key;
    this.amount = amount;
  }
}
export const P2pEdit$OrMapIncrementEdit = (key, amount) =>
  new OrMapIncrementEdit(key, amount);
export const P2pEdit$isOrMapIncrementEdit = (value) =>
  value instanceof OrMapIncrementEdit;
export const P2pEdit$OrMapIncrementEdit$key = (value) => value.key;
export const P2pEdit$OrMapIncrementEdit$0 = (value) => value.key;
export const P2pEdit$OrMapIncrementEdit$amount = (value) => value.amount;
export const P2pEdit$OrMapIncrementEdit$1 = (value) => value.amount;

export class OrMapSetRegisterEdit extends $CustomType {
  constructor(key, value, timestamp) {
    super();
    this.key = key;
    this.value = value;
    this.timestamp = timestamp;
  }
}
export const P2pEdit$OrMapSetRegisterEdit = (key, value, timestamp) =>
  new OrMapSetRegisterEdit(key, value, timestamp);
export const P2pEdit$isOrMapSetRegisterEdit = (value) =>
  value instanceof OrMapSetRegisterEdit;
export const P2pEdit$OrMapSetRegisterEdit$key = (value) => value.key;
export const P2pEdit$OrMapSetRegisterEdit$0 = (value) => value.key;
export const P2pEdit$OrMapSetRegisterEdit$value = (value) => value.value;
export const P2pEdit$OrMapSetRegisterEdit$1 = (value) => value.value;
export const P2pEdit$OrMapSetRegisterEdit$timestamp = (value) =>
  value.timestamp;
export const P2pEdit$OrMapSetRegisterEdit$2 = (value) => value.timestamp;

export class OrMapSetMvRegisterEdit extends $CustomType {
  constructor(key, value) {
    super();
    this.key = key;
    this.value = value;
  }
}
export const P2pEdit$OrMapSetMvRegisterEdit = (key, value) =>
  new OrMapSetMvRegisterEdit(key, value);
export const P2pEdit$isOrMapSetMvRegisterEdit = (value) =>
  value instanceof OrMapSetMvRegisterEdit;
export const P2pEdit$OrMapSetMvRegisterEdit$key = (value) => value.key;
export const P2pEdit$OrMapSetMvRegisterEdit$0 = (value) => value.key;
export const P2pEdit$OrMapSetMvRegisterEdit$value = (value) => value.value;
export const P2pEdit$OrMapSetMvRegisterEdit$1 = (value) => value.value;

export class OrMapRemoveEdit extends $CustomType {
  constructor(key) {
    super();
    this.key = key;
  }
}
export const P2pEdit$OrMapRemoveEdit = (key) => new OrMapRemoveEdit(key);
export const P2pEdit$isOrMapRemoveEdit = (value) =>
  value instanceof OrMapRemoveEdit;
export const P2pEdit$OrMapRemoveEdit$key = (value) => value.key;
export const P2pEdit$OrMapRemoveEdit$0 = (value) => value.key;

export class OrMapAddMemberEdit extends $CustomType {
  constructor(key, member) {
    super();
    this.key = key;
    this.member = member;
  }
}
export const P2pEdit$OrMapAddMemberEdit = (key, member) =>
  new OrMapAddMemberEdit(key, member);
export const P2pEdit$isOrMapAddMemberEdit = (value) =>
  value instanceof OrMapAddMemberEdit;
export const P2pEdit$OrMapAddMemberEdit$key = (value) => value.key;
export const P2pEdit$OrMapAddMemberEdit$0 = (value) => value.key;
export const P2pEdit$OrMapAddMemberEdit$member = (value) => value.member;
export const P2pEdit$OrMapAddMemberEdit$1 = (value) => value.member;

export class OrMapRemoveMemberEdit extends $CustomType {
  constructor(key, member) {
    super();
    this.key = key;
    this.member = member;
  }
}
export const P2pEdit$OrMapRemoveMemberEdit = (key, member) =>
  new OrMapRemoveMemberEdit(key, member);
export const P2pEdit$isOrMapRemoveMemberEdit = (value) =>
  value instanceof OrMapRemoveMemberEdit;
export const P2pEdit$OrMapRemoveMemberEdit$key = (value) => value.key;
export const P2pEdit$OrMapRemoveMemberEdit$0 = (value) => value.key;
export const P2pEdit$OrMapRemoveMemberEdit$member = (value) => value.member;
export const P2pEdit$OrMapRemoveMemberEdit$1 = (value) => value.member;

export class OrSetAddEdit extends $CustomType {
  constructor(element) {
    super();
    this.element = element;
  }
}
export const P2pEdit$OrSetAddEdit = (element) => new OrSetAddEdit(element);
export const P2pEdit$isOrSetAddEdit = (value) => value instanceof OrSetAddEdit;
export const P2pEdit$OrSetAddEdit$element = (value) => value.element;
export const P2pEdit$OrSetAddEdit$0 = (value) => value.element;

export class OrSetRemoveEdit extends $CustomType {
  constructor(element) {
    super();
    this.element = element;
  }
}
export const P2pEdit$OrSetRemoveEdit = (element) =>
  new OrSetRemoveEdit(element);
export const P2pEdit$isOrSetRemoveEdit = (value) =>
  value instanceof OrSetRemoveEdit;
export const P2pEdit$OrSetRemoveEdit$element = (value) => value.element;
export const P2pEdit$OrSetRemoveEdit$0 = (value) => value.element;

export class GSetAddEdit extends $CustomType {
  constructor(element) {
    super();
    this.element = element;
  }
}
export const P2pEdit$GSetAddEdit = (element) => new GSetAddEdit(element);
export const P2pEdit$isGSetAddEdit = (value) => value instanceof GSetAddEdit;
export const P2pEdit$GSetAddEdit$element = (value) => value.element;
export const P2pEdit$GSetAddEdit$0 = (value) => value.element;

export class TwoPSetAddEdit extends $CustomType {
  constructor(element) {
    super();
    this.element = element;
  }
}
export const P2pEdit$TwoPSetAddEdit = (element) => new TwoPSetAddEdit(element);
export const P2pEdit$isTwoPSetAddEdit = (value) =>
  value instanceof TwoPSetAddEdit;
export const P2pEdit$TwoPSetAddEdit$element = (value) => value.element;
export const P2pEdit$TwoPSetAddEdit$0 = (value) => value.element;

export class TwoPSetRemoveEdit extends $CustomType {
  constructor(element) {
    super();
    this.element = element;
  }
}
export const P2pEdit$TwoPSetRemoveEdit = (element) =>
  new TwoPSetRemoveEdit(element);
export const P2pEdit$isTwoPSetRemoveEdit = (value) =>
  value instanceof TwoPSetRemoveEdit;
export const P2pEdit$TwoPSetRemoveEdit$element = (value) => value.element;
export const P2pEdit$TwoPSetRemoveEdit$0 = (value) => value.element;

export class SequenceInsertEdit extends $CustomType {
  constructor(index, value) {
    super();
    this.index = index;
    this.value = value;
  }
}
export const P2pEdit$SequenceInsertEdit = (index, value) =>
  new SequenceInsertEdit(index, value);
export const P2pEdit$isSequenceInsertEdit = (value) =>
  value instanceof SequenceInsertEdit;
export const P2pEdit$SequenceInsertEdit$index = (value) => value.index;
export const P2pEdit$SequenceInsertEdit$0 = (value) => value.index;
export const P2pEdit$SequenceInsertEdit$value = (value) => value.value;
export const P2pEdit$SequenceInsertEdit$1 = (value) => value.value;

export class SequenceDeleteEdit extends $CustomType {
  constructor(index) {
    super();
    this.index = index;
  }
}
export const P2pEdit$SequenceDeleteEdit = (index) =>
  new SequenceDeleteEdit(index);
export const P2pEdit$isSequenceDeleteEdit = (value) =>
  value instanceof SequenceDeleteEdit;
export const P2pEdit$SequenceDeleteEdit$index = (value) => value.index;
export const P2pEdit$SequenceDeleteEdit$0 = (value) => value.index;

export class SequenceMoveEdit extends $CustomType {
  constructor(from_index, to_index) {
    super();
    this.from_index = from_index;
    this.to_index = to_index;
  }
}
export const P2pEdit$SequenceMoveEdit = (from_index, to_index) =>
  new SequenceMoveEdit(from_index, to_index);
export const P2pEdit$isSequenceMoveEdit = (value) =>
  value instanceof SequenceMoveEdit;
export const P2pEdit$SequenceMoveEdit$from_index = (value) => value.from_index;
export const P2pEdit$SequenceMoveEdit$0 = (value) => value.from_index;
export const P2pEdit$SequenceMoveEdit$to_index = (value) => value.to_index;
export const P2pEdit$SequenceMoveEdit$1 = (value) => value.to_index;

export class SequenceReplaceEdit extends $CustomType {
  constructor(index, value) {
    super();
    this.index = index;
    this.value = value;
  }
}
export const P2pEdit$SequenceReplaceEdit = (index, value) =>
  new SequenceReplaceEdit(index, value);
export const P2pEdit$isSequenceReplaceEdit = (value) =>
  value instanceof SequenceReplaceEdit;
export const P2pEdit$SequenceReplaceEdit$index = (value) => value.index;
export const P2pEdit$SequenceReplaceEdit$0 = (value) => value.index;
export const P2pEdit$SequenceReplaceEdit$value = (value) => value.value;
export const P2pEdit$SequenceReplaceEdit$1 = (value) => value.value;

export class TextInsertEdit extends $CustomType {
  constructor(index, value) {
    super();
    this.index = index;
    this.value = value;
  }
}
export const P2pEdit$TextInsertEdit = (index, value) =>
  new TextInsertEdit(index, value);
export const P2pEdit$isTextInsertEdit = (value) =>
  value instanceof TextInsertEdit;
export const P2pEdit$TextInsertEdit$index = (value) => value.index;
export const P2pEdit$TextInsertEdit$0 = (value) => value.index;
export const P2pEdit$TextInsertEdit$value = (value) => value.value;
export const P2pEdit$TextInsertEdit$1 = (value) => value.value;

export class TextDeleteRangeEdit extends $CustomType {
  constructor(start, end) {
    super();
    this.start = start;
    this.end = end;
  }
}
export const P2pEdit$TextDeleteRangeEdit = (start, end) =>
  new TextDeleteRangeEdit(start, end);
export const P2pEdit$isTextDeleteRangeEdit = (value) =>
  value instanceof TextDeleteRangeEdit;
export const P2pEdit$TextDeleteRangeEdit$start = (value) => value.start;
export const P2pEdit$TextDeleteRangeEdit$0 = (value) => value.start;
export const P2pEdit$TextDeleteRangeEdit$end = (value) => value.end;
export const P2pEdit$TextDeleteRangeEdit$1 = (value) => value.end;

export class TextReplaceRangeEdit extends $CustomType {
  constructor(start, end, value) {
    super();
    this.start = start;
    this.end = end;
    this.value = value;
  }
}
export const P2pEdit$TextReplaceRangeEdit = (start, end, value) =>
  new TextReplaceRangeEdit(start, end, value);
export const P2pEdit$isTextReplaceRangeEdit = (value) =>
  value instanceof TextReplaceRangeEdit;
export const P2pEdit$TextReplaceRangeEdit$start = (value) => value.start;
export const P2pEdit$TextReplaceRangeEdit$0 = (value) => value.start;
export const P2pEdit$TextReplaceRangeEdit$end = (value) => value.end;
export const P2pEdit$TextReplaceRangeEdit$1 = (value) => value.end;
export const P2pEdit$TextReplaceRangeEdit$value = (value) => value.value;
export const P2pEdit$TextReplaceRangeEdit$2 = (value) => value.value;

export class TextAppendEdit extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
export const P2pEdit$TextAppendEdit = (value) => new TextAppendEdit(value);
export const P2pEdit$isTextAppendEdit = (value) =>
  value instanceof TextAppendEdit;
export const P2pEdit$TextAppendEdit$value = (value) => value.value;
export const P2pEdit$TextAppendEdit$0 = (value) => value.value;

export class MapEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$MapEvent = ($0) => new MapEvent($0);
export const ChannelEvent$isMapEvent = (value) => value instanceof MapEvent;
export const ChannelEvent$MapEvent$0 = (value) => value[0];

export class CounterEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$CounterEvent = ($0) => new CounterEvent($0);
export const ChannelEvent$isCounterEvent = (value) =>
  value instanceof CounterEvent;
export const ChannelEvent$CounterEvent$0 = (value) => value[0];

export class PnCounterEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$PnCounterEvent = ($0) => new PnCounterEvent($0);
export const ChannelEvent$isPnCounterEvent = (value) =>
  value instanceof PnCounterEvent;
export const ChannelEvent$PnCounterEvent$0 = (value) => value[0];

export class GCounterEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$GCounterEvent = ($0) => new GCounterEvent($0);
export const ChannelEvent$isGCounterEvent = (value) =>
  value instanceof GCounterEvent;
export const ChannelEvent$GCounterEvent$0 = (value) => value[0];

export class LwwRegisterEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$LwwRegisterEvent = ($0) => new LwwRegisterEvent($0);
export const ChannelEvent$isLwwRegisterEvent = (value) =>
  value instanceof LwwRegisterEvent;
export const ChannelEvent$LwwRegisterEvent$0 = (value) => value[0];

export class LwwMapEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$LwwMapEvent = ($0) => new LwwMapEvent($0);
export const ChannelEvent$isLwwMapEvent = (value) =>
  value instanceof LwwMapEvent;
export const ChannelEvent$LwwMapEvent$0 = (value) => value[0];

export class MvRegisterEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$MvRegisterEvent = ($0) => new MvRegisterEvent($0);
export const ChannelEvent$isMvRegisterEvent = (value) =>
  value instanceof MvRegisterEvent;
export const ChannelEvent$MvRegisterEvent$0 = (value) => value[0];

export class OrMapEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$OrMapEvent = ($0) => new OrMapEvent($0);
export const ChannelEvent$isOrMapEvent = (value) => value instanceof OrMapEvent;
export const ChannelEvent$OrMapEvent$0 = (value) => value[0];

export class OrSetEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$OrSetEvent = ($0) => new OrSetEvent($0);
export const ChannelEvent$isOrSetEvent = (value) => value instanceof OrSetEvent;
export const ChannelEvent$OrSetEvent$0 = (value) => value[0];

export class GSetEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$GSetEvent = ($0) => new GSetEvent($0);
export const ChannelEvent$isGSetEvent = (value) => value instanceof GSetEvent;
export const ChannelEvent$GSetEvent$0 = (value) => value[0];

export class TwoPSetEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$TwoPSetEvent = ($0) => new TwoPSetEvent($0);
export const ChannelEvent$isTwoPSetEvent = (value) =>
  value instanceof TwoPSetEvent;
export const ChannelEvent$TwoPSetEvent$0 = (value) => value[0];

export class RegisterCollectionEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$RegisterCollectionEvent = ($0) =>
  new RegisterCollectionEvent($0);
export const ChannelEvent$isRegisterCollectionEvent = (value) =>
  value instanceof RegisterCollectionEvent;
export const ChannelEvent$RegisterCollectionEvent$0 = (value) => value[0];

export class ClaimsEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$ClaimsEvent = ($0) => new ClaimsEvent($0);
export const ChannelEvent$isClaimsEvent = (value) =>
  value instanceof ClaimsEvent;
export const ChannelEvent$ClaimsEvent$0 = (value) => value[0];

export class TaskManagerEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$TaskManagerEvent = ($0) => new TaskManagerEvent($0);
export const ChannelEvent$isTaskManagerEvent = (value) =>
  value instanceof TaskManagerEvent;
export const ChannelEvent$TaskManagerEvent$0 = (value) => value[0];

export class PactMapEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$PactMapEvent = ($0) => new PactMapEvent($0);
export const ChannelEvent$isPactMapEvent = (value) =>
  value instanceof PactMapEvent;
export const ChannelEvent$PactMapEvent$0 = (value) => value[0];

export class JsonOtEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$JsonOtEvent = ($0) => new JsonOtEvent($0);
export const ChannelEvent$isJsonOtEvent = (value) =>
  value instanceof JsonOtEvent;
export const ChannelEvent$JsonOtEvent$0 = (value) => value[0];

export class DirectoryEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$DirectoryEvent = ($0) => new DirectoryEvent($0);
export const ChannelEvent$isDirectoryEvent = (value) =>
  value instanceof DirectoryEvent;
export const ChannelEvent$DirectoryEvent$0 = (value) => value[0];

export class OrderedCollectionEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$OrderedCollectionEvent = ($0) =>
  new OrderedCollectionEvent($0);
export const ChannelEvent$isOrderedCollectionEvent = (value) =>
  value instanceof OrderedCollectionEvent;
export const ChannelEvent$OrderedCollectionEvent$0 = (value) => value[0];

export class SequenceEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$SequenceEvent = ($0) => new SequenceEvent($0);
export const ChannelEvent$isSequenceEvent = (value) =>
  value instanceof SequenceEvent;
export const ChannelEvent$SequenceEvent$0 = (value) => value[0];

export class RichTextEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$RichTextEvent = ($0) => new RichTextEvent($0);
export const ChannelEvent$isRichTextEvent = (value) =>
  value instanceof RichTextEvent;
export const ChannelEvent$RichTextEvent$0 = (value) => value[0];

export class TextEvent extends $CustomType {
  constructor($0) {
    super();
    this[0] = $0;
  }
}
export const ChannelEvent$TextEvent = ($0) => new TextEvent($0);
export const ChannelEvent$isTextEvent = (value) => value instanceof TextEvent;
export const ChannelEvent$TextEvent$0 = (value) => value[0];

export class MapSnapshot extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}
export const Snapshot$MapSnapshot = (entries) => new MapSnapshot(entries);
export const Snapshot$isMapSnapshot = (value) => value instanceof MapSnapshot;
export const Snapshot$MapSnapshot$entries = (value) => value.entries;
export const Snapshot$MapSnapshot$0 = (value) => value.entries;

export class CounterSnapshot extends $CustomType {
  constructor(value) {
    super();
    this.value = value;
  }
}
export const Snapshot$CounterSnapshot = (value) => new CounterSnapshot(value);
export const Snapshot$isCounterSnapshot = (value) =>
  value instanceof CounterSnapshot;
export const Snapshot$CounterSnapshot$value = (value) => value.value;
export const Snapshot$CounterSnapshot$0 = (value) => value.value;

export class PnCounterSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$PnCounterSnapshot = (state) =>
  new PnCounterSnapshot(state);
export const Snapshot$isPnCounterSnapshot = (value) =>
  value instanceof PnCounterSnapshot;
export const Snapshot$PnCounterSnapshot$state = (value) => value.state;
export const Snapshot$PnCounterSnapshot$0 = (value) => value.state;

export class GCounterSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$GCounterSnapshot = (state) => new GCounterSnapshot(state);
export const Snapshot$isGCounterSnapshot = (value) =>
  value instanceof GCounterSnapshot;
export const Snapshot$GCounterSnapshot$state = (value) => value.state;
export const Snapshot$GCounterSnapshot$0 = (value) => value.state;

export class LwwRegisterSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$LwwRegisterSnapshot = (state) =>
  new LwwRegisterSnapshot(state);
export const Snapshot$isLwwRegisterSnapshot = (value) =>
  value instanceof LwwRegisterSnapshot;
export const Snapshot$LwwRegisterSnapshot$state = (value) => value.state;
export const Snapshot$LwwRegisterSnapshot$0 = (value) => value.state;

export class LwwMapSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$LwwMapSnapshot = (state) => new LwwMapSnapshot(state);
export const Snapshot$isLwwMapSnapshot = (value) =>
  value instanceof LwwMapSnapshot;
export const Snapshot$LwwMapSnapshot$state = (value) => value.state;
export const Snapshot$LwwMapSnapshot$0 = (value) => value.state;

export class MvRegisterSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$MvRegisterSnapshot = (state) =>
  new MvRegisterSnapshot(state);
export const Snapshot$isMvRegisterSnapshot = (value) =>
  value instanceof MvRegisterSnapshot;
export const Snapshot$MvRegisterSnapshot$state = (value) => value.state;
export const Snapshot$MvRegisterSnapshot$0 = (value) => value.state;

export class OrMapSnapshot extends $CustomType {
  constructor(mode, state) {
    super();
    this.mode = mode;
    this.state = state;
  }
}
export const Snapshot$OrMapSnapshot = (mode, state) =>
  new OrMapSnapshot(mode, state);
export const Snapshot$isOrMapSnapshot = (value) =>
  value instanceof OrMapSnapshot;
export const Snapshot$OrMapSnapshot$mode = (value) => value.mode;
export const Snapshot$OrMapSnapshot$0 = (value) => value.mode;
export const Snapshot$OrMapSnapshot$state = (value) => value.state;
export const Snapshot$OrMapSnapshot$1 = (value) => value.state;

export class OrSetSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$OrSetSnapshot = (state) => new OrSetSnapshot(state);
export const Snapshot$isOrSetSnapshot = (value) =>
  value instanceof OrSetSnapshot;
export const Snapshot$OrSetSnapshot$state = (value) => value.state;
export const Snapshot$OrSetSnapshot$0 = (value) => value.state;

export class GSetSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$GSetSnapshot = (state) => new GSetSnapshot(state);
export const Snapshot$isGSetSnapshot = (value) => value instanceof GSetSnapshot;
export const Snapshot$GSetSnapshot$state = (value) => value.state;
export const Snapshot$GSetSnapshot$0 = (value) => value.state;

export class TwoPSetSnapshot extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$TwoPSetSnapshot = (state) => new TwoPSetSnapshot(state);
export const Snapshot$isTwoPSetSnapshot = (value) =>
  value instanceof TwoPSetSnapshot;
export const Snapshot$TwoPSetSnapshot$state = (value) => value.state;
export const Snapshot$TwoPSetSnapshot$0 = (value) => value.state;

export class RegisterCollectionSnapshot extends $CustomType {
  constructor(registers) {
    super();
    this.registers = registers;
  }
}
export const Snapshot$RegisterCollectionSnapshot = (registers) =>
  new RegisterCollectionSnapshot(registers);
export const Snapshot$isRegisterCollectionSnapshot = (value) =>
  value instanceof RegisterCollectionSnapshot;
export const Snapshot$RegisterCollectionSnapshot$registers = (value) =>
  value.registers;
export const Snapshot$RegisterCollectionSnapshot$0 = (value) => value.registers;

export class ClaimsSnapshot extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}
export const Snapshot$ClaimsSnapshot = (entries) => new ClaimsSnapshot(entries);
export const Snapshot$isClaimsSnapshot = (value) =>
  value instanceof ClaimsSnapshot;
export const Snapshot$ClaimsSnapshot$entries = (value) => value.entries;
export const Snapshot$ClaimsSnapshot$0 = (value) => value.entries;

export class TaskManagerSnapshot extends $CustomType {
  constructor(queues) {
    super();
    this.queues = queues;
  }
}
export const Snapshot$TaskManagerSnapshot = (queues) =>
  new TaskManagerSnapshot(queues);
export const Snapshot$isTaskManagerSnapshot = (value) =>
  value instanceof TaskManagerSnapshot;
export const Snapshot$TaskManagerSnapshot$queues = (value) => value.queues;
export const Snapshot$TaskManagerSnapshot$0 = (value) => value.queues;

export class PactMapSnapshot extends $CustomType {
  constructor(entries) {
    super();
    this.entries = entries;
  }
}
export const Snapshot$PactMapSnapshot = (entries) =>
  new PactMapSnapshot(entries);
export const Snapshot$isPactMapSnapshot = (value) =>
  value instanceof PactMapSnapshot;
export const Snapshot$PactMapSnapshot$entries = (value) => value.entries;
export const Snapshot$PactMapSnapshot$0 = (value) => value.entries;

export class JsonOtSnapshot extends $CustomType {
  constructor(document) {
    super();
    this.document = document;
  }
}
export const Snapshot$JsonOtSnapshot = (document) =>
  new JsonOtSnapshot(document);
export const Snapshot$isJsonOtSnapshot = (value) =>
  value instanceof JsonOtSnapshot;
export const Snapshot$JsonOtSnapshot$document = (value) => value.document;
export const Snapshot$JsonOtSnapshot$0 = (value) => value.document;

export class DirectorySnapshot extends $CustomType {
  constructor(summary) {
    super();
    this.summary = summary;
  }
}
export const Snapshot$DirectorySnapshot = (summary) =>
  new DirectorySnapshot(summary);
export const Snapshot$isDirectorySnapshot = (value) =>
  value instanceof DirectorySnapshot;
export const Snapshot$DirectorySnapshot$summary = (value) => value.summary;
export const Snapshot$DirectorySnapshot$0 = (value) => value.summary;

export class OrderedCollectionSnapshot extends $CustomType {
  constructor(queue, jobs) {
    super();
    this.queue = queue;
    this.jobs = jobs;
  }
}
export const Snapshot$OrderedCollectionSnapshot = (queue, jobs) =>
  new OrderedCollectionSnapshot(queue, jobs);
export const Snapshot$isOrderedCollectionSnapshot = (value) =>
  value instanceof OrderedCollectionSnapshot;
export const Snapshot$OrderedCollectionSnapshot$queue = (value) => value.queue;
export const Snapshot$OrderedCollectionSnapshot$0 = (value) => value.queue;
export const Snapshot$OrderedCollectionSnapshot$jobs = (value) => value.jobs;
export const Snapshot$OrderedCollectionSnapshot$1 = (value) => value.jobs;

export class SequenceSummary extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$SequenceSummary = (state) => new SequenceSummary(state);
export const Snapshot$isSequenceSummary = (value) =>
  value instanceof SequenceSummary;
export const Snapshot$SequenceSummary$state = (value) => value.state;
export const Snapshot$SequenceSummary$0 = (value) => value.state;

export class RichTextSnapshot extends $CustomType {
  constructor(document) {
    super();
    this.document = document;
  }
}
export const Snapshot$RichTextSnapshot = (document) =>
  new RichTextSnapshot(document);
export const Snapshot$isRichTextSnapshot = (value) =>
  value instanceof RichTextSnapshot;
export const Snapshot$RichTextSnapshot$document = (value) => value.document;
export const Snapshot$RichTextSnapshot$0 = (value) => value.document;

export class TextSummary extends $CustomType {
  constructor(state) {
    super();
    this.state = state;
  }
}
export const Snapshot$TextSummary = (state) => new TextSummary(state);
export const Snapshot$isTextSummary = (value) => value instanceof TextSummary;
export const Snapshot$TextSummary$state = (value) => value.state;
export const Snapshot$TextSummary$0 = (value) => value.state;

export class ClaimResolved extends $CustomType {
  constructor(key, outcome) {
    super();
    this.key = key;
    this.outcome = outcome;
  }
}
export const Resolution$ClaimResolved = (key, outcome) =>
  new ClaimResolved(key, outcome);
export const Resolution$isClaimResolved = (value) =>
  value instanceof ClaimResolved;
export const Resolution$ClaimResolved$key = (value) => value.key;
export const Resolution$ClaimResolved$0 = (value) => value.key;
export const Resolution$ClaimResolved$outcome = (value) => value.outcome;
export const Resolution$ClaimResolved$1 = (value) => value.outcome;

export class AcquireResolved extends $CustomType {
  constructor(acquire_id, outcome) {
    super();
    this.acquire_id = acquire_id;
    this.outcome = outcome;
  }
}
export const Resolution$AcquireResolved = (acquire_id, outcome) =>
  new AcquireResolved(acquire_id, outcome);
export const Resolution$isAcquireResolved = (value) =>
  value instanceof AcquireResolved;
export const Resolution$AcquireResolved$acquire_id = (value) =>
  value.acquire_id;
export const Resolution$AcquireResolved$0 = (value) => value.acquire_id;
export const Resolution$AcquireResolved$outcome = (value) => value.outcome;
export const Resolution$AcquireResolved$1 = (value) => value.outcome;

export class NoMeta extends $CustomType {}
export const LocalOperationMeta$NoMeta$const = new NoMeta();
export const LocalOperationMeta$NoMeta = () => LocalOperationMeta$NoMeta$const;
export const LocalOperationMeta$isNoMeta = (value) => value instanceof NoMeta;

export class CounterMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$CounterMeta = (message_id) =>
  new CounterMeta(message_id);
export const LocalOperationMeta$isCounterMeta = (value) =>
  value instanceof CounterMeta;
export const LocalOperationMeta$CounterMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$CounterMeta$0 = (value) => value.message_id;

export class PnCounterMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$PnCounterMeta = (message_id) =>
  new PnCounterMeta(message_id);
export const LocalOperationMeta$isPnCounterMeta = (value) =>
  value instanceof PnCounterMeta;
export const LocalOperationMeta$PnCounterMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$PnCounterMeta$0 = (value) => value.message_id;

export class GCounterMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$GCounterMeta = (message_id) =>
  new GCounterMeta(message_id);
export const LocalOperationMeta$isGCounterMeta = (value) =>
  value instanceof GCounterMeta;
export const LocalOperationMeta$GCounterMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$GCounterMeta$0 = (value) => value.message_id;

export class LwwRegisterMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$LwwRegisterMeta = (message_id) =>
  new LwwRegisterMeta(message_id);
export const LocalOperationMeta$isLwwRegisterMeta = (value) =>
  value instanceof LwwRegisterMeta;
export const LocalOperationMeta$LwwRegisterMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$LwwRegisterMeta$0 = (value) => value.message_id;

export class LwwMapMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$LwwMapMeta = (message_id) =>
  new LwwMapMeta(message_id);
export const LocalOperationMeta$isLwwMapMeta = (value) =>
  value instanceof LwwMapMeta;
export const LocalOperationMeta$LwwMapMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$LwwMapMeta$0 = (value) => value.message_id;

export class MvRegisterMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$MvRegisterMeta = (message_id) =>
  new MvRegisterMeta(message_id);
export const LocalOperationMeta$isMvRegisterMeta = (value) =>
  value instanceof MvRegisterMeta;
export const LocalOperationMeta$MvRegisterMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$MvRegisterMeta$0 = (value) => value.message_id;

export class OrMapMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$OrMapMeta = (message_id) =>
  new OrMapMeta(message_id);
export const LocalOperationMeta$isOrMapMeta = (value) =>
  value instanceof OrMapMeta;
export const LocalOperationMeta$OrMapMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$OrMapMeta$0 = (value) => value.message_id;

export class OrSetMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$OrSetMeta = (message_id) =>
  new OrSetMeta(message_id);
export const LocalOperationMeta$isOrSetMeta = (value) =>
  value instanceof OrSetMeta;
export const LocalOperationMeta$OrSetMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$OrSetMeta$0 = (value) => value.message_id;

export class GSetMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$GSetMeta = (message_id) =>
  new GSetMeta(message_id);
export const LocalOperationMeta$isGSetMeta = (value) =>
  value instanceof GSetMeta;
export const LocalOperationMeta$GSetMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$GSetMeta$0 = (value) => value.message_id;

export class TwoPSetMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$TwoPSetMeta = (message_id) =>
  new TwoPSetMeta(message_id);
export const LocalOperationMeta$isTwoPSetMeta = (value) =>
  value instanceof TwoPSetMeta;
export const LocalOperationMeta$TwoPSetMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$TwoPSetMeta$0 = (value) => value.message_id;

export class TaskManagerMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$TaskManagerMeta = (message_id) =>
  new TaskManagerMeta(message_id);
export const LocalOperationMeta$isTaskManagerMeta = (value) =>
  value instanceof TaskManagerMeta;
export const LocalOperationMeta$TaskManagerMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$TaskManagerMeta$0 = (value) => value.message_id;

export class DirectoryMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$DirectoryMeta = (message_id) =>
  new DirectoryMeta(message_id);
export const LocalOperationMeta$isDirectoryMeta = (value) =>
  value instanceof DirectoryMeta;
export const LocalOperationMeta$DirectoryMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$DirectoryMeta$0 = (value) => value.message_id;

export class SequenceMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$SequenceMeta = (message_id) =>
  new SequenceMeta(message_id);
export const LocalOperationMeta$isSequenceMeta = (value) =>
  value instanceof SequenceMeta;
export const LocalOperationMeta$SequenceMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$SequenceMeta$0 = (value) => value.message_id;

export class TextMeta extends $CustomType {
  constructor(message_id) {
    super();
    this.message_id = message_id;
  }
}
export const LocalOperationMeta$TextMeta = (message_id) =>
  new TextMeta(message_id);
export const LocalOperationMeta$isTextMeta = (value) =>
  value instanceof TextMeta;
export const LocalOperationMeta$TextMeta$message_id = (value) =>
  value.message_id;
export const LocalOperationMeta$TextMeta$0 = (value) => value.message_id;

export class SequencedMeta extends $CustomType {
  constructor(sequence_number, last_seen_sequence_number, minimum_sequence_number, author, self, quorum, roster, reference_sequence_number) {
    super();
    this.sequence_number = sequence_number;
    this.last_seen_sequence_number = last_seen_sequence_number;
    this.minimum_sequence_number = minimum_sequence_number;
    this.author = author;
    this.self = self;
    this.quorum = quorum;
    this.roster = roster;
    this.reference_sequence_number = reference_sequence_number;
  }
}
export const SequencedMeta$SequencedMeta = (sequence_number, last_seen_sequence_number, minimum_sequence_number, author, self, quorum, roster, reference_sequence_number) =>
  new SequencedMeta(sequence_number,
  last_seen_sequence_number,
  minimum_sequence_number,
  author,
  self,
  quorum,
  roster,
  reference_sequence_number);
export const SequencedMeta$isSequencedMeta = (value) =>
  value instanceof SequencedMeta;
export const SequencedMeta$SequencedMeta$sequence_number = (value) =>
  value.sequence_number;
export const SequencedMeta$SequencedMeta$0 = (value) => value.sequence_number;
export const SequencedMeta$SequencedMeta$last_seen_sequence_number = (value) =>
  value.last_seen_sequence_number;
export const SequencedMeta$SequencedMeta$1 = (value) =>
  value.last_seen_sequence_number;
export const SequencedMeta$SequencedMeta$minimum_sequence_number = (value) =>
  value.minimum_sequence_number;
export const SequencedMeta$SequencedMeta$2 = (value) =>
  value.minimum_sequence_number;
export const SequencedMeta$SequencedMeta$author = (value) => value.author;
export const SequencedMeta$SequencedMeta$3 = (value) => value.author;
export const SequencedMeta$SequencedMeta$self = (value) => value.self;
export const SequencedMeta$SequencedMeta$4 = (value) => value.self;
export const SequencedMeta$SequencedMeta$quorum = (value) => value.quorum;
export const SequencedMeta$SequencedMeta$5 = (value) => value.quorum;
export const SequencedMeta$SequencedMeta$roster = (value) => value.roster;
export const SequencedMeta$SequencedMeta$6 = (value) => value.roster;
export const SequencedMeta$SequencedMeta$reference_sequence_number = (value) =>
  value.reference_sequence_number;
export const SequencedMeta$SequencedMeta$7 = (value) =>
  value.reference_sequence_number;

/**
 * An ack did not agree with the pending queue of the kernel. This error is
 * fatal. The runtime routed an ack for an operation that the kernel never
 * submitted, or it routed the acks out of order.
 */
export class UnexpectedAck extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const ChannelError$UnexpectedAck = (detail) => new UnexpectedAck(detail);
export const ChannelError$isUnexpectedAck = (value) =>
  value instanceof UnexpectedAck;
export const ChannelError$UnexpectedAck$detail = (value) => value.detail;
export const ChannelError$UnexpectedAck$0 = (value) => value.detail;

/**
 * The runtime dispatched an operation to a channel of a different kernel
 * type. This error is fatal. The decoder reads an operation against the
 * registry type for its address, so a mismatch here is a routing fault, and
 * not bad input.
 */
export class WrongChannelType extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const ChannelError$WrongChannelType = (detail) =>
  new WrongChannelType(detail);
export const ChannelError$isWrongChannelType = (value) =>
  value instanceof WrongChannelType;
export const ChannelError$WrongChannelType$detail = (value) => value.detail;
export const ChannelError$WrongChannelType$0 = (value) => value.detail;

export class CorruptRemoteOperation extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const ChannelError$CorruptRemoteOperation = (detail) =>
  new CorruptRemoteOperation(detail);
export const ChannelError$isCorruptRemoteOperation = (value) =>
  value instanceof CorruptRemoteOperation;
export const ChannelError$CorruptRemoteOperation$detail = (value) =>
  value.detail;
export const ChannelError$CorruptRemoteOperation$0 = (value) => value.detail;

export class OrMapOperationFailed extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const ChannelError$OrMapOperationFailed = (detail) =>
  new OrMapOperationFailed(detail);
export const ChannelError$isOrMapOperationFailed = (value) =>
  value instanceof OrMapOperationFailed;
export const ChannelError$OrMapOperationFailed$detail = (value) => value.detail;
export const ChannelError$OrMapOperationFailed$0 = (value) => value.detail;

/**
 * A `P2pEdit` value or an operation does not match the kernel of the
 * channel, or that kernel does not support ack-free p2p at all. See
 * `supports_p2p`.
 *
 * This error also covers a refusal at the edit level from a kernel that
 * does support p2p, for example an OR-map mode mismatch, or a sequence or
 * text edit that is out of bounds. The p2p path has no pending queue to
 * protect, so those refusals arrive here, and not in an error type of that
 * kernel.
 */
export class UnsupportedP2p extends $CustomType {
  constructor(detail) {
    super();
    this.detail = detail;
  }
}
export const ChannelError$UnsupportedP2p = (detail) =>
  new UnsupportedP2p(detail);
export const ChannelError$isUnsupportedP2p = (value) =>
  value instanceof UnsupportedP2p;
export const ChannelError$UnsupportedP2p$detail = (value) => value.detail;
export const ChannelError$UnsupportedP2p$0 = (value) => value.detail;

export const ChannelError$detail = (value) => value.detail;

export function type_to_string(channel_type) {
  if (channel_type instanceof MapChannel) {
    return $wire.channel_type_map;
  } else if (channel_type instanceof CounterChannel) {
    return $wire.channel_type_counter;
  } else if (channel_type instanceof PnCounterChannel) {
    return $wire.channel_type_pn_counter;
  } else if (channel_type instanceof GCounterChannel) {
    return $wire.channel_type_g_counter;
  } else if (channel_type instanceof LwwRegisterChannel) {
    return $wire.channel_type_lww_register;
  } else if (channel_type instanceof LwwMapChannel) {
    return $wire.channel_type_lww_map;
  } else if (channel_type instanceof MvRegisterChannel) {
    return $wire.channel_type_mv_register;
  } else if (channel_type instanceof OrMapChannel) {
    return $wire.channel_type_or_map;
  } else if (channel_type instanceof OrSetChannel) {
    return $wire.channel_type_or_set;
  } else if (channel_type instanceof GSetChannel) {
    return $wire.channel_type_g_set;
  } else if (channel_type instanceof TwoPSetChannel) {
    return $wire.channel_type_two_p_set;
  } else if (channel_type instanceof RegisterCollectionChannel) {
    return $wire.channel_type_register_collection;
  } else if (channel_type instanceof ClaimsChannel) {
    return $wire.channel_type_claims;
  } else if (channel_type instanceof TaskManagerChannel) {
    return $wire.channel_type_task_manager;
  } else if (channel_type instanceof PactMapChannel) {
    return $wire.channel_type_pact_map;
  } else if (channel_type instanceof JsonOtChannel) {
    return $wire.channel_type_json_ot;
  } else if (channel_type instanceof DirectoryChannel) {
    return $wire.channel_type_directory;
  } else if (channel_type instanceof OrderedCollectionChannel) {
    return $wire.channel_type_ordered_collection;
  } else if (channel_type instanceof SequenceChannel) {
    return $wire.channel_type_sequence;
  } else if (channel_type instanceof RichTextChannel) {
    return $wire.channel_type_rich_text;
  } else {
    return $wire.channel_type_text;
  }
}

export function string_to_type(raw) {
  if (raw === ($wire.channel_type_map)) {
    return new Ok(ChannelType$MapChannel$const);
  } else if (raw === ($wire.channel_type_counter)) {
    return new Ok(ChannelType$CounterChannel$const);
  } else if (raw === ($wire.channel_type_pn_counter)) {
    return new Ok(ChannelType$PnCounterChannel$const);
  } else if (raw === ($wire.channel_type_g_counter)) {
    return new Ok(ChannelType$GCounterChannel$const);
  } else if (raw === ($wire.channel_type_lww_register)) {
    return new Ok(ChannelType$LwwRegisterChannel$const);
  } else if (raw === ($wire.channel_type_lww_map)) {
    return new Ok(ChannelType$LwwMapChannel$const);
  } else if (raw === ($wire.channel_type_mv_register)) {
    return new Ok(ChannelType$MvRegisterChannel$const);
  } else if (raw === ($wire.channel_type_or_map)) {
    return new Ok(ChannelType$OrMapChannel$const);
  } else if (raw === ($wire.channel_type_or_set)) {
    return new Ok(ChannelType$OrSetChannel$const);
  } else if (raw === ($wire.channel_type_g_set)) {
    return new Ok(ChannelType$GSetChannel$const);
  } else if (raw === ($wire.channel_type_two_p_set)) {
    return new Ok(ChannelType$TwoPSetChannel$const);
  } else if (raw === ($wire.channel_type_register_collection)) {
    return new Ok(ChannelType$RegisterCollectionChannel$const);
  } else if (raw === ($wire.channel_type_claims)) {
    return new Ok(ChannelType$ClaimsChannel$const);
  } else if (raw === ($wire.channel_type_task_manager)) {
    return new Ok(ChannelType$TaskManagerChannel$const);
  } else if (raw === ($wire.channel_type_pact_map)) {
    return new Ok(ChannelType$PactMapChannel$const);
  } else if (raw === ($wire.channel_type_json_ot)) {
    return new Ok(ChannelType$JsonOtChannel$const);
  } else if (raw === ($wire.channel_type_directory)) {
    return new Ok(ChannelType$DirectoryChannel$const);
  } else if (raw === ($wire.channel_type_ordered_collection)) {
    return new Ok(ChannelType$OrderedCollectionChannel$const);
  } else if (raw === ($wire.channel_type_sequence)) {
    return new Ok(ChannelType$SequenceChannel$const);
  } else if (raw === ($wire.channel_type_rich_text)) {
    return new Ok(ChannelType$RichTextChannel$const);
  } else if (raw === ($wire.channel_type_text)) {
    return new Ok(ChannelType$TextChannel$const);
  } else {
    return new Error(undefined);
  }
}

export function init_type(init) {
  if (init instanceof InitMap) {
    return ChannelType$MapChannel$const;
  } else if (init instanceof InitCounter) {
    return ChannelType$CounterChannel$const;
  } else if (init instanceof InitPnCounter) {
    return ChannelType$PnCounterChannel$const;
  } else if (init instanceof InitGCounter) {
    return ChannelType$GCounterChannel$const;
  } else if (init instanceof InitLwwRegister) {
    return ChannelType$LwwRegisterChannel$const;
  } else if (init instanceof InitLwwMap) {
    return ChannelType$LwwMapChannel$const;
  } else if (init instanceof InitMvRegister) {
    return ChannelType$MvRegisterChannel$const;
  } else if (init instanceof InitOrMap) {
    return ChannelType$OrMapChannel$const;
  } else if (init instanceof InitOrSet) {
    return ChannelType$OrSetChannel$const;
  } else if (init instanceof InitGSet) {
    return ChannelType$GSetChannel$const;
  } else if (init instanceof InitTwoPSet) {
    return ChannelType$TwoPSetChannel$const;
  } else if (init instanceof InitRegisterCollection) {
    return ChannelType$RegisterCollectionChannel$const;
  } else if (init instanceof InitClaims) {
    return ChannelType$ClaimsChannel$const;
  } else if (init instanceof InitTaskManager) {
    return ChannelType$TaskManagerChannel$const;
  } else if (init instanceof InitPactMap) {
    return ChannelType$PactMapChannel$const;
  } else if (init instanceof InitJsonOt) {
    return ChannelType$JsonOtChannel$const;
  } else if (init instanceof InitDirectory) {
    return ChannelType$DirectoryChannel$const;
  } else if (init instanceof InitOrderedCollection) {
    return ChannelType$OrderedCollectionChannel$const;
  } else if (init instanceof InitSequence) {
    return ChannelType$SequenceChannel$const;
  } else if (init instanceof InitRichText) {
    return ChannelType$RichTextChannel$const;
  } else {
    return ChannelType$TextChannel$const;
  }
}

/**
 * Whether the merge behaviour of a channel is correct without a server
 * sequencer.
 */
export function supports_p2p(channel_type) {
  if (channel_type instanceof MapChannel) {
    return false;
  } else if (channel_type instanceof CounterChannel) {
    return false;
  } else if (channel_type instanceof PnCounterChannel) {
    return true;
  } else if (channel_type instanceof GCounterChannel) {
    return true;
  } else if (channel_type instanceof LwwRegisterChannel) {
    return true;
  } else if (channel_type instanceof LwwMapChannel) {
    return true;
  } else if (channel_type instanceof MvRegisterChannel) {
    return true;
  } else if (channel_type instanceof OrMapChannel) {
    return true;
  } else if (channel_type instanceof OrSetChannel) {
    return true;
  } else if (channel_type instanceof GSetChannel) {
    return true;
  } else if (channel_type instanceof TwoPSetChannel) {
    return true;
  } else if (channel_type instanceof RegisterCollectionChannel) {
    return false;
  } else if (channel_type instanceof ClaimsChannel) {
    return false;
  } else if (channel_type instanceof TaskManagerChannel) {
    return false;
  } else if (channel_type instanceof PactMapChannel) {
    return false;
  } else if (channel_type instanceof JsonOtChannel) {
    return false;
  } else if (channel_type instanceof DirectoryChannel) {
    return false;
  } else if (channel_type instanceof OrderedCollectionChannel) {
    return false;
  } else if (channel_type instanceof SequenceChannel) {
    return true;
  } else if (channel_type instanceof RichTextChannel) {
    return false;
  } else {
    return true;
  }
}

export function channel_type(state) {
  if (state instanceof MapState) {
    return ChannelType$MapChannel$const;
  } else if (state instanceof CounterState) {
    return ChannelType$CounterChannel$const;
  } else if (state instanceof PnCounterState) {
    return ChannelType$PnCounterChannel$const;
  } else if (state instanceof GCounterState) {
    return ChannelType$GCounterChannel$const;
  } else if (state instanceof LwwRegisterState) {
    return ChannelType$LwwRegisterChannel$const;
  } else if (state instanceof LwwMapState) {
    return ChannelType$LwwMapChannel$const;
  } else if (state instanceof MvRegisterState) {
    return ChannelType$MvRegisterChannel$const;
  } else if (state instanceof OrMapState) {
    return ChannelType$OrMapChannel$const;
  } else if (state instanceof OrSetState) {
    return ChannelType$OrSetChannel$const;
  } else if (state instanceof GSetState) {
    return ChannelType$GSetChannel$const;
  } else if (state instanceof TwoPSetState) {
    return ChannelType$TwoPSetChannel$const;
  } else if (state instanceof RegisterCollectionState) {
    return ChannelType$RegisterCollectionChannel$const;
  } else if (state instanceof ClaimsState) {
    return ChannelType$ClaimsChannel$const;
  } else if (state instanceof TaskManagerState) {
    return ChannelType$TaskManagerChannel$const;
  } else if (state instanceof PactMapState) {
    return ChannelType$PactMapChannel$const;
  } else if (state instanceof JsonOtState) {
    return ChannelType$JsonOtChannel$const;
  } else if (state instanceof DirectoryState) {
    return ChannelType$DirectoryChannel$const;
  } else if (state instanceof OrderedCollectionState) {
    return ChannelType$OrderedCollectionChannel$const;
  } else if (state instanceof SequenceState) {
    return ChannelType$SequenceChannel$const;
  } else if (state instanceof RichTextState) {
    return ChannelType$RichTextChannel$const;
  } else {
    return ChannelType$TextChannel$const;
  }
}

export function snapshot_type(snapshot) {
  if (snapshot instanceof MapSnapshot) {
    return ChannelType$MapChannel$const;
  } else if (snapshot instanceof CounterSnapshot) {
    return ChannelType$CounterChannel$const;
  } else if (snapshot instanceof PnCounterSnapshot) {
    return ChannelType$PnCounterChannel$const;
  } else if (snapshot instanceof GCounterSnapshot) {
    return ChannelType$GCounterChannel$const;
  } else if (snapshot instanceof LwwRegisterSnapshot) {
    return ChannelType$LwwRegisterChannel$const;
  } else if (snapshot instanceof LwwMapSnapshot) {
    return ChannelType$LwwMapChannel$const;
  } else if (snapshot instanceof MvRegisterSnapshot) {
    return ChannelType$MvRegisterChannel$const;
  } else if (snapshot instanceof OrMapSnapshot) {
    return ChannelType$OrMapChannel$const;
  } else if (snapshot instanceof OrSetSnapshot) {
    return ChannelType$OrSetChannel$const;
  } else if (snapshot instanceof GSetSnapshot) {
    return ChannelType$GSetChannel$const;
  } else if (snapshot instanceof TwoPSetSnapshot) {
    return ChannelType$TwoPSetChannel$const;
  } else if (snapshot instanceof RegisterCollectionSnapshot) {
    return ChannelType$RegisterCollectionChannel$const;
  } else if (snapshot instanceof ClaimsSnapshot) {
    return ChannelType$ClaimsChannel$const;
  } else if (snapshot instanceof TaskManagerSnapshot) {
    return ChannelType$TaskManagerChannel$const;
  } else if (snapshot instanceof PactMapSnapshot) {
    return ChannelType$PactMapChannel$const;
  } else if (snapshot instanceof JsonOtSnapshot) {
    return ChannelType$JsonOtChannel$const;
  } else if (snapshot instanceof DirectorySnapshot) {
    return ChannelType$DirectoryChannel$const;
  } else if (snapshot instanceof OrderedCollectionSnapshot) {
    return ChannelType$OrderedCollectionChannel$const;
  } else if (snapshot instanceof SequenceSummary) {
    return ChannelType$SequenceChannel$const;
  } else if (snapshot instanceof RichTextSnapshot) {
    return ChannelType$RichTextChannel$const;
  } else {
    return ChannelType$TextChannel$const;
  }
}

/**
 * Build an empty channel for one client identity. The map kernel and the
 * counter kernel ignore `replica`. A kernel that is identified by replica uses
 * it as the local CRDT author. A reconnect keeps each existing channel state
 * under its original identity. A load from a summary or an attach calls
 * `from_snapshot` with the current id of the joining client, so that client
 * writes the future deltas.
 */
export function new$(init, replica) {
  if (init instanceof InitMap) {
    return new MapState($map_kernel.new$());
  } else if (init instanceof InitCounter) {
    return new CounterState($counter_kernel.new$());
  } else if (init instanceof InitPnCounter) {
    return new PnCounterState(
      $pn_counter_kernel.new$($replica_id.new$(replica)),
    );
  } else if (init instanceof InitGCounter) {
    return new GCounterState($g_counter_kernel.new$($replica_id.new$(replica)));
  } else if (init instanceof InitLwwRegister) {
    return new LwwRegisterState(
      $lww_register_kernel.new$($replica_id.new$(replica)),
    );
  } else if (init instanceof InitLwwMap) {
    return new LwwMapState($lww_map_kernel.new$($replica_id.new$(replica)));
  } else if (init instanceof InitMvRegister) {
    return new MvRegisterState(
      $mv_register_kernel.new$($replica_id.new$(replica)),
    );
  } else if (init instanceof InitOrMap) {
    let mode = init.mode;
    return new OrMapState($or_map_kernel.new$($replica_id.new$(replica), mode));
  } else if (init instanceof InitOrSet) {
    return new OrSetState($or_set_kernel.new$($replica_id.new$(replica)));
  } else if (init instanceof InitGSet) {
    return new GSetState($g_set_kernel.new$());
  } else if (init instanceof InitTwoPSet) {
    return new TwoPSetState($two_p_set_kernel.new$());
  } else if (init instanceof InitRegisterCollection) {
    return new RegisterCollectionState($register_collection_kernel.new$());
  } else if (init instanceof InitClaims) {
    return new ClaimsState($claims_kernel.new$());
  } else if (init instanceof InitTaskManager) {
    return new TaskManagerState($task_manager_kernel.new$());
  } else if (init instanceof InitPactMap) {
    return new PactMapState($pact_map_kernel.new$());
  } else if (init instanceof InitJsonOt) {
    return new JsonOtState($json_ot_kernel.new$());
  } else if (init instanceof InitDirectory) {
    return new DirectoryState($directory_kernel.new$());
  } else if (init instanceof InitOrderedCollection) {
    return new OrderedCollectionState($ordered_collection_kernel.new$());
  } else if (init instanceof InitSequence) {
    return new SequenceState($sequence_kernel.new$($replica_id.new$(replica)));
  } else if (init instanceof InitRichText) {
    return new RichTextState($rich_text_kernel.new$());
  } else {
    return new TextState($text_kernel.new$($replica_id.new$(replica)));
  }
}

/**
 * The detail text of an or-map kernel error, for a caller that reports a
 * String.
 * 
 * @ignore
 */
function or_map_kernel_error_detail(error) {
  if (error instanceof $or_map_kernel.UnexpectedAck) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $or_map_kernel.UnexpectedRollback) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $or_map_kernel.ModeMismatch) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $or_map_kernel.CorruptDelta) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $or_map_kernel.InvalidSetState) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $or_map_kernel.CounterExhausted) {
    let detail = error.detail;
    return detail;
  } else {
    let detail = error.detail;
    return detail;
  }
}

export function lww_map_error_detail(error) {
  if (error instanceof $lww_map_kernel.UnexpectedAck) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $lww_map_kernel.UnexpectedRollback) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $lww_map_kernel.Clock) {
    let $ = error.error;
    if ($ instanceof $lww_clock.InvalidTimestamp) {
      let value = $.value;
      return "invalid LWW timestamp: " + $int.to_string(value);
    } else {
      return "LWW clock exhausted";
    }
  } else if (error instanceof $lww_map_kernel.InvalidState) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $lww_map_kernel.UnsupportedPruning) {
    let timestamp = error.timestamp;
    return "unsupported LWW map pruning timestamp: " + $int.to_string(timestamp);
  } else {
    return "invalid LWW map JSON";
  }
}

/**
 * Describe a register failure for the channel and runtime error paths.
 */
export function lww_register_error_detail(error) {
  if (error instanceof $lww_register_kernel.UnexpectedAck) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $lww_register_kernel.UnexpectedRollback) {
    let detail = error.detail;
    return detail;
  } else if (error instanceof $lww_register_kernel.Clock) {
    let $ = error.error;
    if ($ instanceof $lww_clock.InvalidTimestamp) {
      let value = $.value;
      return "invalid LWW timestamp: " + $int.to_string(value);
    } else {
      return "LWW clock exhausted";
    }
  } else if (error instanceof $lww_register_kernel.InvalidState) {
    let detail = error.detail;
    return detail;
  } else {
    return "invalid LWW register JSON";
  }
}

/**
 * Build a channel again from a stored snapshot, with the behaviour of
 * `from_sequenced`. The contents of the snapshot become the confirmed state,
 * and nothing is pending.
 *
 * The error arm reports invalid snapshot metadata or an OR-map value mode
 * that does not agree with the mode that the snapshot names.
 */
export function from_snapshot(snapshot, replica) {
  if (snapshot instanceof MapSnapshot) {
    let entries = snapshot.entries;
    return new Ok(new MapState($map_kernel.from_sequenced(entries)));
  } else if (snapshot instanceof CounterSnapshot) {
    let value = snapshot.value;
    return new Ok(new CounterState($counter_kernel.from_summary(value)));
  } else if (snapshot instanceof PnCounterSnapshot) {
    let state = snapshot.state;
    return new Ok(
      new PnCounterState(
        $pn_counter_kernel.from_sequenced(state, $replica_id.new$(replica)),
      ),
    );
  } else if (snapshot instanceof GCounterSnapshot) {
    let state = snapshot.state;
    return new Ok(
      new GCounterState(
        $g_counter_kernel.from_sequenced(state, $replica_id.new$(replica)),
      ),
    );
  } else if (snapshot instanceof LwwRegisterSnapshot) {
    let state = snapshot.state;
    let _pipe = $lww_register_kernel.from_sequenced(
      state,
      $replica_id.new$(replica),
    );
    let _pipe$1 = $result.map(
      _pipe,
      (var0) => { return new LwwRegisterState(var0); },
    );
    return $result.map_error(_pipe$1, lww_register_error_detail);
  } else if (snapshot instanceof LwwMapSnapshot) {
    let state = snapshot.state;
    let _pipe = $lww_map_kernel.from_sequenced(state, $replica_id.new$(replica));
    let _pipe$1 = $result.map(
      _pipe,
      (var0) => { return new LwwMapState(var0); },
    );
    return $result.map_error(_pipe$1, lww_map_error_detail);
  } else if (snapshot instanceof MvRegisterSnapshot) {
    let state = snapshot.state;
    return new Ok(
      new MvRegisterState(
        $mv_register_kernel.from_sequenced(state, $replica_id.new$(replica)),
      ),
    );
  } else if (snapshot instanceof OrMapSnapshot) {
    let mode = snapshot.mode;
    let state = snapshot.state;
    let $ = $or_map_kernel.from_sequenced(
      state,
      mode,
      $replica_id.new$(replica),
    );
    if ($ instanceof Ok) {
      let kernel = $[0];
      return new Ok(new OrMapState(kernel));
    } else {
      let error = $[0];
      return new Error(or_map_kernel_error_detail(error));
    }
  } else if (snapshot instanceof OrSetSnapshot) {
    let state = snapshot.state;
    return new Ok(
      new OrSetState(
        $or_set_kernel.from_sequenced(state, $replica_id.new$(replica)),
      ),
    );
  } else if (snapshot instanceof GSetSnapshot) {
    let state = snapshot.state;
    return new Ok(new GSetState($g_set_kernel.from_sequenced(state)));
  } else if (snapshot instanceof TwoPSetSnapshot) {
    let state = snapshot.state;
    return new Ok(new TwoPSetState($two_p_set_kernel.from_sequenced(state)));
  } else if (snapshot instanceof RegisterCollectionSnapshot) {
    let registers = snapshot.registers;
    return new Ok(
      new RegisterCollectionState(
        $register_collection_kernel.from_summary(registers),
      ),
    );
  } else if (snapshot instanceof ClaimsSnapshot) {
    let entries = snapshot.entries;
    return new Ok(new ClaimsState($claims_kernel.from_summary(entries)));
  } else if (snapshot instanceof TaskManagerSnapshot) {
    let queues = snapshot.queues;
    return new Ok(
      new TaskManagerState($task_manager_kernel.from_summary(queues)),
    );
  } else if (snapshot instanceof PactMapSnapshot) {
    let entries = snapshot.entries;
    return new Ok(new PactMapState($pact_map_kernel.from_summary(entries)));
  } else if (snapshot instanceof JsonOtSnapshot) {
    let document = snapshot.document;
    return new Ok(new JsonOtState($json_ot_kernel.from_summary(document)));
  } else if (snapshot instanceof DirectorySnapshot) {
    let summary = snapshot.summary;
    return new Ok(new DirectoryState($directory_kernel.from_summary(summary)));
  } else if (snapshot instanceof OrderedCollectionSnapshot) {
    let queue = snapshot.queue;
    let jobs = snapshot.jobs;
    return new Ok(
      new OrderedCollectionState(
        $ordered_collection_kernel.from_summary(queue, jobs),
      ),
    );
  } else if (snapshot instanceof SequenceSummary) {
    let state = snapshot.state;
    return new Ok(
      new SequenceState(
        $sequence_kernel.from_sequenced(state, $replica_id.new$(replica)),
      ),
    );
  } else if (snapshot instanceof RichTextSnapshot) {
    let document = snapshot.document;
    return new Ok(new RichTextState($rich_text_kernel.from_summary(document)));
  } else {
    let state = snapshot.state;
    return new Ok(
      new TextState(
        $text_kernel.from_sequenced(state, $replica_id.new$(replica)),
      ),
    );
  }
}

/**
 * The value of the counter kernel is optimistic, because it contains the
 * pending increments. Subtract the amounts that have no ack, for the view of
 * the sequenced data only.
 * 
 * @ignore
 */
function counter_sequenced_value(kernel) {
  return $list.fold(
    kernel.pending,
    kernel.value,
    (value, pending) => { return value - pending.increment_amount; },
  );
}

/**
 * The confirmed state, which contains the sequenced data only, as a summary
 * captures it.
 */
export function snapshot(state) {
  if (state instanceof MapState) {
    let kernel = state[0];
    return new MapSnapshot($map_kernel.sequenced_entries(kernel));
  } else if (state instanceof CounterState) {
    let kernel = state[0];
    return new CounterSnapshot(counter_sequenced_value(kernel));
  } else if (state instanceof PnCounterState) {
    let kernel = state[0];
    return new PnCounterSnapshot(kernel.sequenced);
  } else if (state instanceof GCounterState) {
    let kernel = state[0];
    return new GCounterSnapshot(kernel.sequenced);
  } else if (state instanceof LwwRegisterState) {
    let kernel = state[0];
    return new LwwRegisterSnapshot(kernel.sequenced);
  } else if (state instanceof LwwMapState) {
    let kernel = state[0];
    return new LwwMapSnapshot(kernel.sequenced);
  } else if (state instanceof MvRegisterState) {
    let kernel = state[0];
    return new MvRegisterSnapshot(kernel.sequenced);
  } else if (state instanceof OrMapState) {
    let kernel = state[0];
    return new OrMapSnapshot(kernel.mode, kernel.sequenced);
  } else if (state instanceof OrSetState) {
    let kernel = state[0];
    return new OrSetSnapshot(kernel.sequenced);
  } else if (state instanceof GSetState) {
    let kernel = state[0];
    return new GSetSnapshot(kernel.sequenced);
  } else if (state instanceof TwoPSetState) {
    let kernel = state[0];
    return new TwoPSetSnapshot(kernel.sequenced);
  } else if (state instanceof RegisterCollectionState) {
    let kernel = state[0];
    return new RegisterCollectionSnapshot(
      $register_collection_kernel.summary_registers(kernel),
    );
  } else if (state instanceof ClaimsState) {
    let kernel = state[0];
    return new ClaimsSnapshot($claims_kernel.summary_entries(kernel));
  } else if (state instanceof TaskManagerState) {
    let kernel = state[0];
    return new TaskManagerSnapshot($task_manager_kernel.summary_queues(kernel));
  } else if (state instanceof PactMapState) {
    let kernel = state[0];
    return new PactMapSnapshot($pact_map_kernel.summary_entries(kernel));
  } else if (state instanceof JsonOtState) {
    let kernel = state[0];
    return new JsonOtSnapshot($json_ot_kernel.summary(kernel));
  } else if (state instanceof DirectoryState) {
    let kernel = state[0];
    return new DirectorySnapshot($directory_kernel.summary_tree(kernel));
  } else if (state instanceof OrderedCollectionState) {
    let kernel = state[0];
    return new OrderedCollectionSnapshot(
      $ordered_collection_kernel.summary_queue(kernel),
      $ordered_collection_kernel.summary_jobs(kernel),
    );
  } else if (state instanceof SequenceState) {
    let kernel = state[0];
    return new SequenceSummary(kernel.sequenced);
  } else if (state instanceof RichTextState) {
    let kernel = state[0];
    return new RichTextSnapshot($rich_text_kernel.summary(kernel));
  } else {
    let kernel = state[0];
    return new TextSummary(kernel.sequenced);
  }
}

/**
 * The current optimistic view, as an attach operation captures it. Every local
 * edit of a detached channel is pending, so this function must include them,
 * and `snapshot` does not.
 */
export function attach_snapshot(state) {
  if (state instanceof MapState) {
    let kernel = state[0];
    return new MapSnapshot($map_kernel.entries(kernel));
  } else if (state instanceof CounterState) {
    let kernel = state[0];
    return new CounterSnapshot(kernel.value);
  } else if (state instanceof PnCounterState) {
    let kernel = state[0];
    return new PnCounterSnapshot(kernel.optimistic);
  } else if (state instanceof GCounterState) {
    let kernel = state[0];
    return new GCounterSnapshot(kernel.optimistic);
  } else if (state instanceof LwwRegisterState) {
    let kernel = state[0];
    return new LwwRegisterSnapshot(kernel.optimistic);
  } else if (state instanceof LwwMapState) {
    let kernel = state[0];
    return new LwwMapSnapshot(kernel.optimistic);
  } else if (state instanceof MvRegisterState) {
    let kernel = state[0];
    return new MvRegisterSnapshot(kernel.optimistic);
  } else if (state instanceof OrMapState) {
    let kernel = state[0];
    return new OrMapSnapshot(kernel.mode, kernel.optimistic);
  } else if (state instanceof OrSetState) {
    let kernel = state[0];
    return new OrSetSnapshot(kernel.optimistic);
  } else if (state instanceof GSetState) {
    let kernel = state[0];
    return new GSetSnapshot(kernel.optimistic);
  } else if (state instanceof TwoPSetState) {
    let kernel = state[0];
    return new TwoPSetSnapshot(kernel.optimistic);
  } else if (state instanceof RegisterCollectionState) {
    let kernel = state[0];
    return new RegisterCollectionSnapshot(
      $register_collection_kernel.summary_registers(kernel),
    );
  } else if (state instanceof ClaimsState) {
    let kernel = state[0];
    return new ClaimsSnapshot($claims_kernel.summary_entries(kernel));
  } else if (state instanceof TaskManagerState) {
    let kernel = state[0];
    return new TaskManagerSnapshot($task_manager_kernel.summary_queues(kernel));
  } else if (state instanceof PactMapState) {
    let kernel = state[0];
    return new PactMapSnapshot($pact_map_kernel.summary_entries(kernel));
  } else if (state instanceof JsonOtState) {
    let kernel = state[0];
    let $ = $json_ot_kernel.view(kernel);
    if ($ instanceof Ok) {
      let document = $[0];
      return new JsonOtSnapshot(document);
    } else {
      return new JsonOtSnapshot($json_ot_kernel.summary(kernel));
    }
  } else if (state instanceof DirectoryState) {
    let kernel = state[0];
    return new DirectorySnapshot($directory_kernel.summary_tree(kernel));
  } else if (state instanceof OrderedCollectionState) {
    let kernel = state[0];
    return new OrderedCollectionSnapshot(
      $ordered_collection_kernel.summary_queue(kernel),
      $ordered_collection_kernel.summary_jobs(kernel),
    );
  } else if (state instanceof SequenceState) {
    let kernel = state[0];
    return new SequenceSummary(kernel.optimistic);
  } else if (state instanceof RichTextState) {
    let kernel = state[0];
    let $ = $rich_text_kernel.view(kernel);
    if ($ instanceof Ok) {
      let document = $[0];
      return new RichTextSnapshot(document);
    } else {
      return new RichTextSnapshot($rich_text_kernel.summary(kernel));
    }
  } else {
    let kernel = state[0];
    return new TextSummary(kernel.optimistic);
  }
}

export function attach_state(state, replica) {
  if (state instanceof MapState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof CounterState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof PnCounterState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof GCounterState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof LwwRegisterState) {
    let kernel = state[0];
    return new LwwRegisterState(
      new $lww_register_kernel.LwwRegisterState(
        $replica_id.new$(replica),
        kernel.optimistic,
        kernel.optimistic,
        $List$Empty$const,
        kernel.next_pending_message_id,
        kernel.last_seen,
      ),
    );
  } else if (state instanceof LwwMapState) {
    let kernel = state[0];
    return new LwwMapState(
      $lww_map_kernel.promote_attach(
        new $lww_map_kernel.LwwMapState(
          $replica_id.new$(replica),
          kernel.sequenced,
          kernel.optimistic,
          kernel.pending,
          kernel.next_pending_message_id,
          kernel.last_seen,
        ),
      ),
    );
  } else if (state instanceof MvRegisterState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof OrMapState) {
    let kernel = state[0];
    return new OrMapState($or_map_kernel.promote_attach(kernel));
  } else if (state instanceof OrSetState) {
    let kernel = state[0];
    return new OrSetState($or_set_kernel.promote_attach(kernel));
  } else if (state instanceof GSetState) {
    let kernel = state[0];
    return new GSetState($g_set_kernel.promote_attach(kernel));
  } else if (state instanceof TwoPSetState) {
    let kernel = state[0];
    return new TwoPSetState($two_p_set_kernel.promote_attach(kernel));
  } else if (state instanceof RegisterCollectionState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof ClaimsState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof TaskManagerState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof PactMapState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof JsonOtState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof DirectoryState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof OrderedCollectionState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else if (state instanceof SequenceState) {
    let kernel = state[0];
    return new SequenceState($sequence_kernel.promote_attach(kernel));
  } else if (state instanceof RichTextState) {
    let $ = from_snapshot(attach_snapshot(state), replica);
    if ($ instanceof Ok) {
      let attached = $[0];
      return attached;
    } else {
      return state;
    }
  } else {
    let kernel = state[0];
    return new TextState($text_kernel.promote_attach(kernel));
  }
}

function wrong_channel_type(state, context) {
  return new WrongChannelType(
    ((context + " does not match the ") + type_to_string(channel_type(state))) + " channel it was routed to",
  );
}

/**
 * A detail string for a person to read, for a failure in the pure rich-text
 * algebra. The caller puts it in a `ChannelError` value.
 * 
 * @ignore
 */
function rich_text_error_detail(error) {
  if (error instanceof $rich_text.Malformed) {
    let component = error.component;
    let reason = error.reason;
    return (("rich-text malformed " + component) + ": ") + reason;
  } else if (error instanceof $rich_text.InvalidApply) {
    let reason = error.reason;
    return "rich-text invalid apply: " + reason;
  } else {
    let offset = error.offset;
    return "rich-text invalid boundary at offset " + $int.to_string(offset);
  }
}

/**
 * Build the `SequencedMeta` value of the directory kernel, from the metadata
 * at the channel level and the kernel `message_id` of the operation, which is
 * its client-sequence identity.
 * 
 * @ignore
 */
function directory_sequenced_meta(meta, message_id) {
  return new $directory_kernel.SequencedMeta(
    meta.author,
    meta.sequence_number,
    meta.reference_sequence_number,
    message_id,
  );
}

/**
 * A detail string for a person to read, for a failure in the pure json0
 * algebra. The caller puts it in a `ChannelError` value.
 * 
 * @ignore
 */
function json_ot_error_detail(error) {
  if (error instanceof $json_ot.BadPath) {
    let detail = error.detail;
    return "json0 bad path: " + detail;
  } else if (error instanceof $json_ot.BadValue) {
    let detail = error.detail;
    return "json0 bad value: " + detail;
  } else {
    let name = error.name;
    return "json0 unknown subtype: " + name;
  }
}

/**
 * The reaction to a PactMap `Set` operation, as an owed operation at the
 * channel level. The runtime submits it by itself.
 * 
 * @ignore
 */
function pact_map_reaction_operations(reaction) {
  if (reaction instanceof $pact_map_kernel.OweAccept) {
    let operation = reaction.operation;
    return toList([new PactMapOperation(operation)]);
  } else {
    return $List$Empty$const;
  }
}

/**
 * Apply a sequenced PactMap operation. A `Set` operation goes to `apply_set`,
 * which can owe an `Accept` operation when this client is a signoff. An
 * `Accept` operation goes to `apply_accept`. A local operation and a remote
 * operation both take this path, and the runtime uses `is_own_operation` only
 * to reclaim the in-flight entry. The PactMap of FluidFramework applies an
 * operation at its sequence point, whoever wrote it.
 * 
 * @ignore
 */
function apply_pact_map(kernel, operation, meta) {
  if (operation instanceof $pact_map_kernel.Set) {
    let $ = $pact_map_kernel.apply_set(
      kernel,
      operation,
      meta.sequence_number,
      meta.quorum,
      meta.self,
    );
    let kernel$1 = $[0];
    let events = $[1];
    let reaction = $[2];
    return new Ok(
      [
        new PactMapState(kernel$1),
        $list.map(events, (var0) => { return new PactMapEvent(var0); }),
        pact_map_reaction_operations(reaction),
      ],
    );
  } else {
    let key = operation.key;
    let $ = $pact_map_kernel.apply_accept(
      kernel,
      key,
      meta.author,
      meta.sequence_number,
    );
    if ($ instanceof Ok) {
      let kernel$1 = $[0][0];
      let events = $[0][1];
      return new Ok(
        [
          new PactMapState(kernel$1),
          $list.map(events, (var0) => { return new PactMapEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      let detail = $[0].detail;
      return new Error(new CorruptRemoteOperation(detail));
    }
  }
}

/**
 * Apply a sequenced operation from another client.
 *
 * The function returns the new state, the events that it produced, and the
 * follow-up operations that the kernel *owes*. The runtime submits an owed
 * operation by itself, with a new CSN and a new in-flight entry, in reaction
 * to this operation. For example, a consensus kernel emits its own `Accept`
 * operation after it reads a `Set` operation from a peer. Most kernels owe
 * nothing and return an empty list. The runtime buffers the owed operations of
 * each channel, and it sends them after the current sequenced batch. See
 * `runtime_core.collect_released_operations`.
 */
export function apply_remote(state, operation, meta) {
  if (state instanceof MapState) {
    if (operation instanceof MapOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $map_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new MapState(kernel$1),
          $list.map(events, (var0) => { return new MapEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof CounterState) {
    if (operation instanceof CounterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $counter_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new CounterState(kernel$1),
          $list.map(events, (var0) => { return new CounterEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof PnCounterState) {
    if (operation instanceof PnCounterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $pn_counter_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new PnCounterState(kernel$1),
          $list.map(events, (var0) => { return new PnCounterEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof GCounterState) {
    if (operation instanceof GCounterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $g_counter_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new GCounterState(kernel$1),
          $list.map(events, (var0) => { return new GCounterEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof LwwRegisterState) {
    if (operation instanceof LwwRegisterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $lww_register_kernel.apply_remote(kernel, operation$1);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        return new Ok(
          [
            new LwwRegisterState(kernel$1),
            $list.map(events, (var0) => { return new LwwRegisterEvent(var0); }),
            $List$Empty$const,
          ],
        );
      } else {
        let error = $[0];
        return new Error(
          new CorruptRemoteOperation(lww_register_error_detail(error)),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof LwwMapState) {
    if (operation instanceof LwwMapOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let _pipe = $lww_map_kernel.apply_remote(kernel, operation$1);
      let _pipe$1 = $result.map(
        _pipe,
        (pair) => {
          return [
            new LwwMapState(pair[0]),
            $list.map(pair[1], (var0) => { return new LwwMapEvent(var0); }),
            $List$Empty$const,
          ];
        },
      );
      return $result.map_error(
        _pipe$1,
        (error) => {
          return new CorruptRemoteOperation(lww_map_error_detail(error));
        },
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof MvRegisterState) {
    if (operation instanceof MvRegisterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $mv_register_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new MvRegisterState(kernel$1),
          $list.map(events, (var0) => { return new MvRegisterEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof OrMapState) {
    if (operation instanceof OrMapOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $or_map_kernel.apply_remote(kernel, operation$1);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        return new Ok(
          [
            new OrMapState(kernel$1),
            $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            $List$Empty$const,
          ],
        );
      } else {
        let $1 = $[0];
        if ($1 instanceof $or_map_kernel.UnexpectedAck) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else if ($1 instanceof $or_map_kernel.UnexpectedRollback) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else if ($1 instanceof $or_map_kernel.ModeMismatch) {
          let detail = $1.detail;
          return new Error(new CorruptRemoteOperation(detail));
        } else if ($1 instanceof $or_map_kernel.CorruptDelta) {
          let detail = $1.detail;
          return new Error(new CorruptRemoteOperation(detail));
        } else if ($1 instanceof $or_map_kernel.InvalidSetState) {
          let detail = $1.detail;
          return new Error(new OrMapOperationFailed(detail));
        } else if ($1 instanceof $or_map_kernel.CounterExhausted) {
          let detail = $1.detail;
          return new Error(new OrMapOperationFailed(detail));
        } else {
          let detail = $1.detail;
          return new Error(new CorruptRemoteOperation(detail));
        }
      }
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof OrSetState) {
    if (operation instanceof OrSetOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $or_set_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new OrSetState(kernel$1),
          $list.map(events, (var0) => { return new OrSetEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof GSetState) {
    if (operation instanceof GSetOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $g_set_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new GSetState(kernel$1),
          $list.map(events, (var0) => { return new GSetEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof TwoPSetState) {
    if (operation instanceof TwoPSetOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $two_p_set_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new TwoPSetState(kernel$1),
          $list.map(events, (var0) => { return new TwoPSetEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof RegisterCollectionState) {
    if (operation instanceof RegisterCollectionOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $register_collection_kernel.apply_remote(
        kernel,
        operation$1,
        meta.sequence_number,
      );
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new RegisterCollectionState(kernel$1),
          $list.map(
            events,
            (var0) => { return new RegisterCollectionEvent(var0); },
          ),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof ClaimsState) {
    if (operation instanceof ClaimsOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $claims_kernel.apply_remote(
        kernel,
        operation$1,
        meta.sequence_number,
      );
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new ClaimsState(kernel$1),
          $list.map(events, (var0) => { return new ClaimsEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof TaskManagerState) {
    if (operation instanceof TaskManagerOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $task_manager_kernel.apply_remote(
        kernel,
        operation$1,
        meta.author,
        meta.roster,
      );
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new TaskManagerState(kernel$1),
          $list.map(events, (var0) => { return new TaskManagerEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof PactMapState) {
    if (operation instanceof PactMapOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      return apply_pact_map(kernel, operation$1, meta);
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof JsonOtState) {
    if (operation instanceof JsonOtOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $json_ot_kernel.apply_remote(
        kernel,
        operation$1,
        meta.sequence_number,
        meta.minimum_sequence_number,
      );
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        return new Ok(
          [
            new JsonOtState(kernel$1),
            $list.map(events, (var0) => { return new JsonOtEvent(var0); }),
            $List$Empty$const,
          ],
        );
      } else {
        let $1 = $[0];
        if ($1 instanceof $json_ot_kernel.UnexpectedAck) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else {
          let error = $1.error;
          return new Error(
            new CorruptRemoteOperation(json_ot_error_detail(error)),
          );
        }
      }
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof DirectoryState) {
    if (operation instanceof DirectoryOperation) {
      let kernel = state[0];
      let operation$1 = operation.operation;
      let message_id = operation.message_id;
      let $ = $directory_kernel.apply_remote(
        kernel,
        operation$1,
        directory_sequenced_meta(meta, message_id),
        meta.self,
      );
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new DirectoryState(kernel$1),
          $list.map(events, (var0) => { return new DirectoryEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof OrderedCollectionState) {
    if (operation instanceof OrderedCollectionOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $ordered_collection_kernel.apply_remote(
        kernel,
        operation$1,
        meta.author,
      );
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new OrderedCollectionState(kernel$1),
          $list.map(
            events,
            (var0) => { return new OrderedCollectionEvent(var0); },
          ),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof SequenceState) {
    if (operation instanceof SequenceOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $sequence_kernel.apply_remote(kernel, operation$1);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new SequenceState(kernel$1),
          $list.map(events, (var0) => { return new SequenceEvent(var0); }),
          $List$Empty$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (state instanceof RichTextState) {
    if (operation instanceof RichTextOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $rich_text_kernel.apply_remote(
        kernel,
        operation$1,
        meta.sequence_number,
        meta.minimum_sequence_number,
      );
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        return new Ok(
          [
            new RichTextState(kernel$1),
            $list.map(events, (var0) => { return new RichTextEvent(var0); }),
            $List$Empty$const,
          ],
        );
      } else {
        let $1 = $[0];
        if ($1 instanceof $rich_text_kernel.UnexpectedAck) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else {
          let error = $1.error;
          return new Error(
            new CorruptRemoteOperation(rich_text_error_detail(error)),
          );
        }
      }
    } else {
      return new Error(wrong_channel_type(state, "remote op"));
    }
  } else if (operation instanceof TextOperation) {
    let kernel = state[0];
    let operation$1 = operation[0];
    let $ = $text_kernel.apply_remote(kernel, operation$1);
    let kernel$1 = $[0];
    let events = $[1];
    return new Ok(
      [
        new TextState(kernel$1),
        $list.map(events, (var0) => { return new TextEvent(var0); }),
        $List$Empty$const,
      ],
    );
  } else {
    return new Error(wrong_channel_type(state, "remote op"));
  }
}

/**
 * Whether a channel applies its *own* sequenced operations through
 * `apply_remote`, which is the path of a remote operation, and not through the
 * optimistic `ack_local`. A consensus kernel, such as PactMap, takes effect at
 * the sequence point only, whoever wrote the operation. The runtime thus
 * reclaims the in-flight entry and then applies the operation with
 * `apply_remote`. Every optimistic kernel returns `False` and acks the
 * operation locally.
 */
export function applies_own_on_sequence(state) {
  if (state instanceof MapState) {
    return false;
  } else if (state instanceof CounterState) {
    return false;
  } else if (state instanceof PnCounterState) {
    return false;
  } else if (state instanceof GCounterState) {
    return false;
  } else if (state instanceof LwwRegisterState) {
    return false;
  } else if (state instanceof LwwMapState) {
    return false;
  } else if (state instanceof MvRegisterState) {
    return false;
  } else if (state instanceof OrMapState) {
    return false;
  } else if (state instanceof OrSetState) {
    return false;
  } else if (state instanceof GSetState) {
    return false;
  } else if (state instanceof TwoPSetState) {
    return false;
  } else if (state instanceof RegisterCollectionState) {
    return false;
  } else if (state instanceof ClaimsState) {
    return false;
  } else if (state instanceof TaskManagerState) {
    return false;
  } else if (state instanceof PactMapState) {
    return true;
  } else if (state instanceof JsonOtState) {
    return false;
  } else if (state instanceof DirectoryState) {
    return false;
  } else if (state instanceof OrderedCollectionState) {
    return false;
  } else if (state instanceof SequenceState) {
    return false;
  } else if (state instanceof RichTextState) {
    return false;
  } else {
    return false;
  }
}

/**
 * Apply a sequenced membership leave to a channel. The named client left the
 * collaboration session at `leave_sequence_number`.
 *
 * A consensus kernel or a queue kernel that tracks state for each client
 * settles that state deterministically. PactMap removes the outstanding
 * signoffs of that client, so a pending value that waits on it can settle.
 * ConsensusOrderedCollection returns the jobs of that client to the queue.
 * TaskManager removes that client from every task queue. A kernel with no
 * membership behaviour does nothing. The runtime calls this function on every
 * attached channel when it receives a `"leave"` system message.
 */
export function on_leave(state, client_id, leave_sequence_number) {
  if (state instanceof MapState) {
    return [state, $List$Empty$const];
  } else if (state instanceof CounterState) {
    return [state, $List$Empty$const];
  } else if (state instanceof PnCounterState) {
    return [state, $List$Empty$const];
  } else if (state instanceof GCounterState) {
    return [state, $List$Empty$const];
  } else if (state instanceof LwwRegisterState) {
    return [state, $List$Empty$const];
  } else if (state instanceof LwwMapState) {
    return [state, $List$Empty$const];
  } else if (state instanceof MvRegisterState) {
    return [state, $List$Empty$const];
  } else if (state instanceof OrMapState) {
    return [state, $List$Empty$const];
  } else if (state instanceof OrSetState) {
    return [state, $List$Empty$const];
  } else if (state instanceof GSetState) {
    return [state, $List$Empty$const];
  } else if (state instanceof TwoPSetState) {
    return [state, $List$Empty$const];
  } else if (state instanceof RegisterCollectionState) {
    return [state, $List$Empty$const];
  } else if (state instanceof ClaimsState) {
    return [state, $List$Empty$const];
  } else if (state instanceof TaskManagerState) {
    let kernel = state[0];
    let $ = $task_manager_kernel.remove_client(kernel, client_id);
    let kernel$1 = $[0];
    let events = $[1];
    return [
      new TaskManagerState(kernel$1),
      $list.map(events, (var0) => { return new TaskManagerEvent(var0); }),
    ];
  } else if (state instanceof PactMapState) {
    let kernel = state[0];
    let $ = $pact_map_kernel.remove_member(
      kernel,
      client_id,
      leave_sequence_number,
    );
    let kernel$1 = $[0];
    let events = $[1];
    return [
      new PactMapState(kernel$1),
      $list.map(events, (var0) => { return new PactMapEvent(var0); }),
    ];
  } else if (state instanceof JsonOtState) {
    return [state, $List$Empty$const];
  } else if (state instanceof DirectoryState) {
    return [state, $List$Empty$const];
  } else if (state instanceof OrderedCollectionState) {
    let kernel = state[0];
    let $ = $ordered_collection_kernel.remove_client(
      kernel,
      new Some(client_id),
    );
    let kernel$1 = $[0];
    let events = $[1];
    return [
      new OrderedCollectionState(kernel$1),
      $list.map(events, (var0) => { return new OrderedCollectionEvent(var0); }),
    ];
  } else if (state instanceof SequenceState) {
    return [state, $List$Empty$const];
  } else if (state instanceof RichTextState) {
    return [state, $List$Empty$const];
  } else {
    return [state, $List$Empty$const];
  }
}

function directory_error_detail(error) {
  if (error instanceof $directory_kernel.UnexpectedAck) {
    let detail = error.detail;
    return "directory ack: " + detail;
  } else if (error instanceof $directory_kernel.UnexpectedRollback) {
    let detail = error.detail;
    return "directory rollback: " + detail;
  } else if (error instanceof $directory_kernel.PathNotFound) {
    let path = error.path;
    return "directory path not found: " + path;
  } else if (error instanceof $directory_kernel.InvalidName) {
    let name = error.name;
    return "directory invalid name: " + name;
  } else {
    let detail = error.detail;
    return "directory invariant: " + detail;
  }
}

/**
 * Commit an acked local operation, which moves it from `pending` to
 * `sequenced`.
 */
export function ack_local(state, operation, local, meta) {
  if (state instanceof MapState) {
    if (operation instanceof MapOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $map_kernel.ack_local(kernel, operation$1);
      if ($ instanceof Ok) {
        let kernel$1 = $[0];
        return new Ok(
          [new MapState(kernel$1), $List$Empty$const, Option$None$const],
        );
      } else {
        let detail = $[0].detail;
        return new Error(new UnexpectedAck(detail));
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof CounterState) {
    if (operation instanceof CounterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("counter ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        let message_id = local.message_id;
        let $ = $counter_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new CounterState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $counter_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("counter ack has pn-counter metadata"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("counter ack has g-counter metadata"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("counter ack has LWW register metadata"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(new UnexpectedAck("counter ack has LWW map metadata"));
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("counter ack has mv-register metadata"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(new UnexpectedAck("counter ack has or-map metadata"));
      } else if (local instanceof OrSetMeta) {
        return new Error(new UnexpectedAck("counter ack has or-set metadata"));
      } else if (local instanceof GSetMeta) {
        return new Error(new UnexpectedAck("counter ack has g-set metadata"));
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("counter ack has two-p-set metadata"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("counter ack has task-manager metadata"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("counter ack has directory metadata"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(new UnexpectedAck("counter ack has sequence metadata"));
      } else {
        return new Error(new UnexpectedAck("counter ack has text metadata"));
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof PnCounterState) {
    if (operation instanceof PnCounterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has counter metadata"),
        );
      } else if (local instanceof PnCounterMeta) {
        let message_id = local.message_id;
        let $ = $pn_counter_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new PnCounterState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $pn_counter_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has g-counter metadata"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has LWW register metadata"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has LWW map metadata"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has mv-register metadata"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has or-map metadata"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has or-set metadata"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(new UnexpectedAck("pn-counter ack has g-set metadata"));
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has two-p-set metadata"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has task-manager metadata"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has directory metadata"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("pn-counter ack has sequence metadata"),
        );
      } else {
        return new Error(new UnexpectedAck("pn-counter ack has text metadata"));
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof GCounterState) {
    if (operation instanceof GCounterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        let message_id = local.message_id;
        let $ = $g_counter_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new GCounterState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $g_counter_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("g-counter ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof LwwRegisterState) {
    if (operation instanceof LwwRegisterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        let message_id = local.message_id;
        let _pipe = $lww_register_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        let _pipe$1 = $result.map(
          _pipe,
          (kernel) => {
            return [
              new LwwRegisterState(kernel),
              $List$Empty$const,
              Option$None$const,
            ];
          },
        );
        return $result.map_error(
          _pipe$1,
          (error) => {
            return new UnexpectedAck(lww_register_error_detail(error));
          },
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("LWW register ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof LwwMapState) {
    if (operation instanceof LwwMapOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        let message_id = local.message_id;
        let _pipe = $lww_map_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        let _pipe$1 = $result.map(
          _pipe,
          (kernel) => {
            return [
              new LwwMapState(kernel),
              $List$Empty$const,
              Option$None$const,
            ];
          },
        );
        return $result.map_error(
          _pipe$1,
          (error) => { return new UnexpectedAck(lww_map_error_detail(error)); },
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("LWW map ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof MvRegisterState) {
    if (operation instanceof MvRegisterOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        let message_id = local.message_id;
        let $ = $mv_register_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [
              new MvRegisterState(kernel$1),
              $List$Empty$const,
              Option$None$const,
            ],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $mv_register_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("mv-register ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof OrMapState) {
    if (operation instanceof OrMapOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("or-map ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("or-map ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("or-map ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("or-map ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("or-map ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("or-map ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("or-map ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        let message_id = local.message_id;
        let $ = $or_map_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new OrMapState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $or_map_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else if ($1 instanceof $or_map_kernel.UnexpectedRollback) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else if ($1 instanceof $or_map_kernel.ModeMismatch) {
            let detail = $1.detail;
            return new Error(new CorruptRemoteOperation(detail));
          } else if ($1 instanceof $or_map_kernel.CorruptDelta) {
            let detail = $1.detail;
            return new Error(new CorruptRemoteOperation(detail));
          } else if ($1 instanceof $or_map_kernel.InvalidSetState) {
            let detail = $1.detail;
            return new Error(new OrMapOperationFailed(detail));
          } else if ($1 instanceof $or_map_kernel.CounterExhausted) {
            let detail = $1.detail;
            return new Error(new OrMapOperationFailed(detail));
          } else {
            let detail = $1.detail;
            return new Error(new CorruptRemoteOperation(detail));
          }
        }
      } else if (local instanceof OrSetMeta) {
        return new Error(new UnexpectedAck("or-map ack has or-set metadata"));
      } else if (local instanceof GSetMeta) {
        return new Error(new UnexpectedAck("or-map ack has g-set metadata"));
      } else if (local instanceof TwoPSetMeta) {
        return new Error(new UnexpectedAck("or-map ack has two-p-set metadata"));
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("or-map ack has task-manager metadata"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(new UnexpectedAck("or-map ack has directory metadata"));
      } else if (local instanceof SequenceMeta) {
        return new Error(new UnexpectedAck("or-map ack has sequence metadata"));
      } else {
        return new Error(new UnexpectedAck("or-map ack has text metadata"));
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof OrSetState) {
    if (operation instanceof OrSetOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        let message_id = local.message_id;
        let $ = $or_set_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new OrSetState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $or_set_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("or-set ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof GSetState) {
    if (operation instanceof GSetOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        let message_id = local.message_id;
        let $ = $g_set_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new GSetState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $g_set_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("g-set ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof TwoPSetState) {
    if (operation instanceof TwoPSetOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        let message_id = local.message_id;
        let $ = $two_p_set_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new TwoPSetState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $two_p_set_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("two-p-set ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof RegisterCollectionState) {
    if (operation instanceof RegisterCollectionOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $register_collection_kernel.ack_local(
        kernel,
        operation$1,
        meta.sequence_number,
      );
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new RegisterCollectionState(kernel$1),
          $list.map(
            events,
            (var0) => { return new RegisterCollectionEvent(var0); },
          ),
          Option$None$const,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof ClaimsState) {
    if (operation instanceof ClaimsOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $claims_kernel.ack_local(
        kernel,
        operation$1,
        meta.sequence_number,
      );
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let outcome = $[0][2];
        return new Ok(
          [
            new ClaimsState(kernel$1),
            $list.map(events, (var0) => { return new ClaimsEvent(var0); }),
            new Some(new ClaimResolved(operation$1.key, outcome)),
          ],
        );
      } else {
        let $1 = $[0];
        if ($1 instanceof $claims_kernel.AlreadyPendingLocally) {
          let detail = $1.key;
          return new Error(new UnexpectedAck(detail));
        } else if ($1 instanceof $claims_kernel.UnexpectedAck) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        }
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof TaskManagerState) {
    if (operation instanceof TaskManagerOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        let message_id = local.message_id;
        let $ = $task_manager_kernel.ack_local(
          kernel,
          operation$1,
          meta.self,
          message_id,
          meta.roster,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0][0];
          let events = $[0][1];
          return new Ok(
            [
              new TaskManagerState(kernel$1),
              $list.map(
                events,
                (var0) => { return new TaskManagerEvent(var0); },
              ),
              Option$None$const,
            ],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $task_manager_kernel.NotAssigned) {
            let detail = $1.task_id;
            return new Error(new UnexpectedAck(detail));
          } else if ($1 instanceof $task_manager_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else if ($1 instanceof $task_manager_kernel.UnexpectedRollback) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      } else {
        return new Error(
          new UnexpectedAck("task-manager ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof PactMapState) {
    return new Error(wrong_channel_type(state, "local ack"));
  } else if (state instanceof JsonOtState) {
    if (operation instanceof JsonOtOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $json_ot_kernel.ack_local(
        kernel,
        operation$1,
        meta.sequence_number,
        meta.minimum_sequence_number,
      );
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        return new Ok(
          [
            new JsonOtState(kernel$1),
            $list.map(events, (var0) => { return new JsonOtEvent(var0); }),
            Option$None$const,
          ],
        );
      } else {
        let $1 = $[0];
        if ($1 instanceof $json_ot_kernel.UnexpectedAck) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else {
          let error = $1.error;
          return new Error(
            new CorruptRemoteOperation(json_ot_error_detail(error)),
          );
        }
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof DirectoryState) {
    if (operation instanceof DirectoryOperation) {
      let kernel = state[0];
      let operation$1 = operation.operation;
      let message_id = operation.message_id;
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else if (local instanceof DirectoryMeta) {
        let $ = $directory_kernel.ack_local(
          kernel,
          operation$1,
          directory_sequenced_meta(meta, message_id),
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new DirectoryState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let error = $[0];
          return new Error(new UnexpectedAck(directory_error_detail(error)));
        }
      } else if (local instanceof SequenceMeta) {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      } else {
        return new Error(
          new UnexpectedAck("directory ack is missing its local metadata"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof OrderedCollectionState) {
    if (operation instanceof OrderedCollectionOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $ordered_collection_kernel.ack_local(
        kernel,
        operation$1,
        meta.self,
      );
      let kernel$1 = $[0];
      let events = $[1];
      let outcome = $[2];
      let _block;
      if (outcome instanceof Some) {
        if (operation$1 instanceof $ordered_collection_kernel.Add) {
          _block = Option$None$const;
        } else if (operation$1 instanceof $ordered_collection_kernel.Acquire) {
          let outcome$1 = outcome[0];
          let acquire_id = operation$1.acquire_id;
          _block = new Some(new AcquireResolved(acquire_id, outcome$1));
        } else if (operation$1 instanceof $ordered_collection_kernel.Complete) {
          _block = Option$None$const;
        } else {
          _block = Option$None$const;
        }
      } else if (operation$1 instanceof $ordered_collection_kernel.Add) {
        _block = Option$None$const;
      } else if (operation$1 instanceof $ordered_collection_kernel.Acquire) {
        _block = outcome;
      } else if (operation$1 instanceof $ordered_collection_kernel.Complete) {
        _block = Option$None$const;
      } else {
        _block = Option$None$const;
      }
      let resolution = _block;
      return new Ok(
        [
          new OrderedCollectionState(kernel$1),
          $list.map(
            events,
            (var0) => { return new OrderedCollectionEvent(var0); },
          ),
          resolution,
        ],
      );
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof SequenceState) {
    if (operation instanceof SequenceOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      if (local instanceof NoMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof CounterMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof PnCounterMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof GCounterMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof LwwRegisterMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof LwwMapMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof MvRegisterMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof OrMapMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof OrSetMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof GSetMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof TwoPSetMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof TaskManagerMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof DirectoryMeta) {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      } else if (local instanceof SequenceMeta) {
        let message_id = local.message_id;
        let $ = $sequence_kernel.ack_local_with_message_id(
          kernel,
          operation$1,
          message_id,
        );
        if ($ instanceof Ok) {
          let kernel$1 = $[0];
          return new Ok(
            [new SequenceState(kernel$1), $List$Empty$const, Option$None$const],
          );
        } else {
          let $1 = $[0];
          if ($1 instanceof $sequence_kernel.UnexpectedAck) {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          } else {
            let detail = $1.detail;
            return new Error(new UnexpectedAck(detail));
          }
        }
      } else {
        return new Error(
          new UnexpectedAck("sequence ack is missing its local message id"),
        );
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (state instanceof RichTextState) {
    if (operation instanceof RichTextOperation) {
      let kernel = state[0];
      let operation$1 = operation[0];
      let $ = $rich_text_kernel.ack_local(
        kernel,
        operation$1,
        meta.sequence_number,
        meta.minimum_sequence_number,
      );
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        return new Ok(
          [
            new RichTextState(kernel$1),
            $list.map(events, (var0) => { return new RichTextEvent(var0); }),
            Option$None$const,
          ],
        );
      } else {
        let $1 = $[0];
        if ($1 instanceof $rich_text_kernel.UnexpectedAck) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else {
          let error = $1.error;
          return new Error(
            new CorruptRemoteOperation(rich_text_error_detail(error)),
          );
        }
      }
    } else {
      return new Error(wrong_channel_type(state, "local ack"));
    }
  } else if (operation instanceof TextOperation) {
    let kernel = state[0];
    let operation$1 = operation[0];
    if (local instanceof NoMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof CounterMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof PnCounterMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof GCounterMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof LwwRegisterMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof LwwMapMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof MvRegisterMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof OrMapMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof OrSetMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof GSetMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof TwoPSetMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof TaskManagerMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof DirectoryMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else if (local instanceof SequenceMeta) {
      return new Error(
        new UnexpectedAck("text ack is missing its local message id"),
      );
    } else {
      let message_id = local.message_id;
      let $ = $text_kernel.ack_local_with_message_id(
        kernel,
        operation$1,
        message_id,
      );
      if ($ instanceof Ok) {
        let kernel$1 = $[0];
        return new Ok(
          [new TextState(kernel$1), $List$Empty$const, Option$None$const],
        );
      } else {
        let $1 = $[0];
        if ($1 instanceof $text_kernel.UnexpectedAck) {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        } else {
          let detail = $1.detail;
          return new Error(new UnexpectedAck(detail));
        }
      }
    }
  } else {
    return new Error(wrong_channel_type(state, "local ack"));
  }
}

/**
 * A detail string for a person to read, for a grow-only counter edit that the
 * kernel refused. The p2p path has no pending queue, so the caller sees this
 * refusal as a `UnsupportedP2p` channel error.
 * 
 * @ignore
 */
function g_counter_edit_detail(error) {
  let amount = error.amount;
  return "g-counter increment must not be negative, got " + $int.to_string(
    amount,
  );
}

function unsupported_p2p(state, context) {
  return new UnsupportedP2p(
    ((context + " does not match the ") + type_to_string(channel_type(state))) + " channel it was routed to",
  );
}

function text_p2p_error(error) {
  return new UnsupportedP2p($text_kernel.edit_error_detail(error));
}

function sequence_p2p_error(error) {
  return new UnsupportedP2p($sequence_kernel.edit_error_detail(error));
}

/**
 * Convert an error of the or-map kernel into a `ChannelError` value, for the
 * p2p paths. A mode mismatch is a refusal at the p2p level, because there is
 * no pending queue to protect. Every other error uses the same conversion as
 * the server-backed `apply_remote` and `ack_local` paths.
 * 
 * @ignore
 */
function or_map_p2p_error(error) {
  if (error instanceof $or_map_kernel.UnexpectedAck) {
    let detail = error.detail;
    return new UnexpectedAck(detail);
  } else if (error instanceof $or_map_kernel.UnexpectedRollback) {
    let detail = error.detail;
    return new UnexpectedAck(detail);
  } else if (error instanceof $or_map_kernel.ModeMismatch) {
    let detail = error.detail;
    return new UnsupportedP2p(detail);
  } else if (error instanceof $or_map_kernel.CorruptDelta) {
    let detail = error.detail;
    return new CorruptRemoteOperation(detail);
  } else if (error instanceof $or_map_kernel.InvalidSetState) {
    let detail = error.detail;
    return new OrMapOperationFailed(detail);
  } else if (error instanceof $or_map_kernel.CounterExhausted) {
    let detail = error.detail;
    return new OrMapOperationFailed(detail);
  } else {
    let detail = error.detail;
    return new CorruptRemoteOperation(detail);
  }
}

/**
 * Write a local p2p edit and merge its delta into the confirmed state and the
 * visible state, in one transition. There is no pending entry and no
 * acknowledgement.
 *
 * The function accepts a channel that `supports_p2p` permits, with the
 * `P2pEdit` variant of that channel. Every other combination returns
 * `UnsupportedP2p`, and it never does nothing quietly. Those combinations are
 * a channel that p2p does not support, and an edit for a different kernel.
 *
 * Every kernel that p2p supports has its own `p2p_*` function, which writes
 * its delta and merges that delta into `sequenced` and `optimistic` directly.
 * See `text_kernel.commit_p2p` for an example. No such path touches `pending`
 * or calls an `ack_local` function.
 */
export function apply_p2p_local(state, edit) {
  if (state instanceof MapState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof CounterState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof PnCounterState) {
    if (edit instanceof PnCounterEdit) {
      let kernel = state[0];
      let amount = edit.amount;
      let $ = $pn_counter_kernel.p2p_update(kernel, amount);
      let kernel$1 = $[0];
      let events = $[1];
      let operation = $[2];
      return new Ok(
        [
          new PnCounterState(kernel$1),
          $list.map(events, (var0) => { return new PnCounterEvent(var0); }),
          new PnCounterOperation(operation),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof GCounterState) {
    if (edit instanceof GCounterIncrementEdit) {
      let kernel = state[0];
      let amount = edit.amount;
      let $ = $g_counter_kernel.p2p_increment(kernel, amount);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new GCounterState(kernel$1),
            $list.map(events, (var0) => { return new GCounterEvent(var0); }),
            new GCounterOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(new UnsupportedP2p(g_counter_edit_detail(error)));
      }
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof LwwRegisterState) {
    if (edit instanceof LwwRegisterSetEdit) {
      let kernel = state[0];
      let value = edit.value;
      let timestamp = edit.timestamp;
      let _pipe = $lww_register_kernel.p2p_set(kernel, value, timestamp);
      let _pipe$1 = $result.map(
        _pipe,
        (result) => {
          return [
            new LwwRegisterState(result[0]),
            $list.map(
              result[1],
              (var0) => { return new LwwRegisterEvent(var0); },
            ),
            new LwwRegisterOperation(result[2]),
          ];
        },
      );
      return $result.map_error(
        _pipe$1,
        (error) => {
          return new UnsupportedP2p(lww_register_error_detail(error));
        },
      );
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof LwwMapState) {
    if (edit instanceof LwwMapSetEdit) {
      let kernel = state[0];
      let key = edit.key;
      let value = edit.value;
      let timestamp = edit.timestamp;
      let _pipe = $lww_map_kernel.p2p_set(kernel, key, value, timestamp);
      let _pipe$1 = $result.map(
        _pipe,
        (result) => {
          return [
            new LwwMapState(result[0]),
            $list.map(result[1], (var0) => { return new LwwMapEvent(var0); }),
            new LwwMapOperation(result[2]),
          ];
        },
      );
      return $result.map_error(
        _pipe$1,
        (error) => { return new UnsupportedP2p(lww_map_error_detail(error)); },
      );
    } else if (edit instanceof LwwMapRemoveEdit) {
      let kernel = state[0];
      let key = edit.key;
      let timestamp = edit.timestamp;
      let _pipe = $lww_map_kernel.p2p_remove(kernel, key, timestamp);
      let _pipe$1 = $result.map(
        _pipe,
        (result) => {
          return [
            new LwwMapState(result[0]),
            $list.map(result[1], (var0) => { return new LwwMapEvent(var0); }),
            new LwwMapOperation(result[2]),
          ];
        },
      );
      return $result.map_error(
        _pipe$1,
        (error) => { return new UnsupportedP2p(lww_map_error_detail(error)); },
      );
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof MvRegisterState) {
    if (edit instanceof MvRegisterEdit) {
      let kernel = state[0];
      let value = edit.value;
      let $ = $mv_register_kernel.p2p_set(kernel, value);
      let kernel$1 = $[0];
      let events = $[1];
      let operation = $[2];
      return new Ok(
        [
          new MvRegisterState(kernel$1),
          $list.map(events, (var0) => { return new MvRegisterEvent(var0); }),
          new MvRegisterOperation(operation),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof OrMapState) {
    if (edit instanceof OrMapIncrementEdit) {
      let kernel = state[0];
      let key = edit.key;
      let amount = edit.amount;
      let $ = $or_map_kernel.p2p_increment(kernel, key, amount);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new OrMapState(kernel$1),
            $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            new OrMapOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(or_map_p2p_error(error));
      }
    } else if (edit instanceof OrMapSetRegisterEdit) {
      let kernel = state[0];
      let key = edit.key;
      let value = edit.value;
      let timestamp = edit.timestamp;
      let $ = $or_map_kernel.p2p_set_register(kernel, key, value, timestamp);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new OrMapState(kernel$1),
            $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            new OrMapOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(or_map_p2p_error(error));
      }
    } else if (edit instanceof OrMapSetMvRegisterEdit) {
      let kernel = state[0];
      let key = edit.key;
      let value = edit.value;
      let $ = $or_map_kernel.p2p_set_mv_register(kernel, key, value);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new OrMapState(kernel$1),
            $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            new OrMapOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(or_map_p2p_error(error));
      }
    } else if (edit instanceof OrMapRemoveEdit) {
      let kernel = state[0];
      let key = edit.key;
      let $ = $or_map_kernel.p2p_remove(kernel, key);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new OrMapState(kernel$1),
            $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            new OrMapOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(or_map_p2p_error(error));
      }
    } else if (edit instanceof OrMapAddMemberEdit) {
      let kernel = state[0];
      let key = edit.key;
      let member = edit.member;
      let $ = $or_map_kernel.p2p_add_member(kernel, key, member);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new OrMapState(kernel$1),
            $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            new OrMapOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(or_map_p2p_error(error));
      }
    } else if (edit instanceof OrMapRemoveMemberEdit) {
      let kernel = state[0];
      let key = edit.key;
      let member = edit.member;
      let $ = $or_map_kernel.p2p_remove_member(kernel, key, member);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new OrMapState(kernel$1),
            $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            new OrMapOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(or_map_p2p_error(error));
      }
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof OrSetState) {
    if (edit instanceof OrSetAddEdit) {
      let kernel = state[0];
      let element = edit.element;
      let $ = $or_set_kernel.p2p_add(kernel, element);
      let kernel$1 = $[0];
      let events = $[1];
      let operation = $[2];
      return new Ok(
        [
          new OrSetState(kernel$1),
          $list.map(events, (var0) => { return new OrSetEvent(var0); }),
          new OrSetOperation(operation),
        ],
      );
    } else if (edit instanceof OrSetRemoveEdit) {
      let kernel = state[0];
      let element = edit.element;
      let $ = $or_set_kernel.p2p_remove(kernel, element);
      let kernel$1 = $[0];
      let events = $[1];
      let operation = $[2];
      return new Ok(
        [
          new OrSetState(kernel$1),
          $list.map(events, (var0) => { return new OrSetEvent(var0); }),
          new OrSetOperation(operation),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof GSetState) {
    if (edit instanceof GSetAddEdit) {
      let kernel = state[0];
      let element = edit.element;
      let $ = $g_set_kernel.p2p_add(kernel, element);
      let kernel$1 = $[0];
      let events = $[1];
      let operation = $[2];
      return new Ok(
        [
          new GSetState(kernel$1),
          $list.map(events, (var0) => { return new GSetEvent(var0); }),
          new GSetOperation(operation),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof TwoPSetState) {
    if (edit instanceof TwoPSetAddEdit) {
      let kernel = state[0];
      let element = edit.element;
      let $ = $two_p_set_kernel.p2p_add(kernel, element);
      let kernel$1 = $[0];
      let events = $[1];
      let operation = $[2];
      return new Ok(
        [
          new TwoPSetState(kernel$1),
          $list.map(events, (var0) => { return new TwoPSetEvent(var0); }),
          new TwoPSetOperation(operation),
        ],
      );
    } else if (edit instanceof TwoPSetRemoveEdit) {
      let kernel = state[0];
      let element = edit.element;
      let $ = $two_p_set_kernel.p2p_remove(kernel, element);
      let kernel$1 = $[0];
      let events = $[1];
      let operation = $[2];
      return new Ok(
        [
          new TwoPSetState(kernel$1),
          $list.map(events, (var0) => { return new TwoPSetEvent(var0); }),
          new TwoPSetOperation(operation),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof RegisterCollectionState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof ClaimsState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof TaskManagerState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof PactMapState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof JsonOtState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof DirectoryState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof OrderedCollectionState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (state instanceof SequenceState) {
    if (edit instanceof SequenceInsertEdit) {
      let kernel = state[0];
      let index = edit.index;
      let value = edit.value;
      let $ = $sequence_kernel.p2p_insert(kernel, index, value);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new SequenceState(kernel$1),
            $list.map(events, (var0) => { return new SequenceEvent(var0); }),
            new SequenceOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(sequence_p2p_error(error));
      }
    } else if (edit instanceof SequenceDeleteEdit) {
      let kernel = state[0];
      let index = edit.index;
      let $ = $sequence_kernel.p2p_delete(kernel, index);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new SequenceState(kernel$1),
            $list.map(events, (var0) => { return new SequenceEvent(var0); }),
            new SequenceOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(sequence_p2p_error(error));
      }
    } else if (edit instanceof SequenceMoveEdit) {
      let kernel = state[0];
      let from_index = edit.from_index;
      let to_index = edit.to_index;
      let $ = $sequence_kernel.p2p_move(kernel, from_index, to_index);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new SequenceState(kernel$1),
            $list.map(events, (var0) => { return new SequenceEvent(var0); }),
            new SequenceOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(sequence_p2p_error(error));
      }
    } else if (edit instanceof SequenceReplaceEdit) {
      let kernel = state[0];
      let index = edit.index;
      let value = edit.value;
      let $ = $sequence_kernel.p2p_replace(kernel, index, value);
      if ($ instanceof Ok) {
        let kernel$1 = $[0][0];
        let events = $[0][1];
        let operation = $[0][2];
        return new Ok(
          [
            new SequenceState(kernel$1),
            $list.map(events, (var0) => { return new SequenceEvent(var0); }),
            new SequenceOperation(operation),
          ],
        );
      } else {
        let error = $[0];
        return new Error(sequence_p2p_error(error));
      }
    } else {
      return new Error(unsupported_p2p(state, "local p2p edit"));
    }
  } else if (state instanceof RichTextState) {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  } else if (edit instanceof TextInsertEdit) {
    let kernel = state[0];
    let index = edit.index;
    let value = edit.value;
    let $ = $text_kernel.p2p_insert(kernel, index, value);
    if ($ instanceof Ok) {
      let kernel$1 = $[0][0];
      let events = $[0][1];
      let operation = $[0][2];
      return new Ok(
        [
          new TextState(kernel$1),
          $list.map(events, (var0) => { return new TextEvent(var0); }),
          new TextOperation(operation),
        ],
      );
    } else {
      let error = $[0];
      return new Error(text_p2p_error(error));
    }
  } else if (edit instanceof TextDeleteRangeEdit) {
    let kernel = state[0];
    let start = edit.start;
    let end = edit.end;
    let $ = $text_kernel.p2p_delete_range(kernel, start, end);
    if ($ instanceof Ok) {
      let kernel$1 = $[0][0];
      let events = $[0][1];
      let operation = $[0][2];
      return new Ok(
        [
          new TextState(kernel$1),
          $list.map(events, (var0) => { return new TextEvent(var0); }),
          new TextOperation(operation),
        ],
      );
    } else {
      let error = $[0];
      return new Error(text_p2p_error(error));
    }
  } else if (edit instanceof TextReplaceRangeEdit) {
    let kernel = state[0];
    let start = edit.start;
    let end = edit.end;
    let value = edit.value;
    let $ = $text_kernel.p2p_replace_range(kernel, start, end, value);
    if ($ instanceof Ok) {
      let kernel$1 = $[0][0];
      let events = $[0][1];
      let operation = $[0][2];
      return new Ok(
        [
          new TextState(kernel$1),
          $list.map(events, (var0) => { return new TextEvent(var0); }),
          new TextOperation(operation),
        ],
      );
    } else {
      let error = $[0];
      return new Error(text_p2p_error(error));
    }
  } else if (edit instanceof TextAppendEdit) {
    let kernel = state[0];
    let value = edit.value;
    let $ = $text_kernel.p2p_append(kernel, value);
    let kernel$1 = $[0];
    let events = $[1];
    let operation = $[2];
    return new Ok(
      [
        new TextState(kernel$1),
        $list.map(events, (var0) => { return new TextEvent(var0); }),
        new TextOperation(operation),
      ],
    );
  } else {
    return new Error(unsupported_p2p(state, "local p2p edit"));
  }
}

/**
 * The metadata that `apply_remote` requires, for the p2p path, which has no
 * metadata. This value is safe, because every kernel that `supports_p2p`
 * permits ignores it.
 * 
 * @ignore
 */
function zeroed_meta() {
  return new SequencedMeta(
    0,
    0,
    0,
    0,
    0,
    $List$Empty$const,
    $List$Empty$const,
    0,
  );
}

/**
 * Merge a remote p2p operation directly into the confirmed state and the
 * visible state. There is no sequence metadata, and there is no pending entry
 * to reclaim. This is the ack-free equivalent of `apply_remote`.
 *
 * None of the seven kernels that p2p supports reads `SequencedMeta`, and none
 * of them owes a follow-up operation. This function thus calls `apply_remote`
 * with a zeroed metadata value, and it discards the list of owed operations.
 * Any other channel, and an operation that does not match the kernel of the
 * channel, returns `UnsupportedP2p`.
 */
export function apply_p2p_remote(state, operation) {
  let $ = supports_p2p(channel_type(state));
  if ($) {
    let $1 = apply_remote(state, operation, zeroed_meta());
    if ($1 instanceof Ok) {
      let state$1 = $1[0][0];
      let events = $1[0][1];
      return new Ok([state$1, events]);
    } else {
      let $2 = $1[0];
      if ($2 instanceof WrongChannelType) {
        return new Error(unsupported_p2p(state, "remote p2p op"));
      } else {
        return $1;
      }
    }
  } else {
    return new Error(unsupported_p2p(state, "remote p2p op"));
  }
}

/**
 * Merge the whole channel snapshot of a peer into the state of this channel.
 * This is the full-state equivalent of `apply_p2p_remote`.
 *
 * Every kernel that p2p supports merges the incoming CRDT state as a lattice
 * join, into the confirmed state and the visible state. A merge is thus
 * idempotent, and it never discards a winner or a local edit. A snapshot for
 * a different kernel, and a snapshot for a channel that does not support
 * ack-free p2p at all, both return `UnsupportedP2p`.
 */
export function merge_p2p_snapshot(state, snapshot) {
  if (state instanceof MapState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof CounterState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof PnCounterState) {
    if (snapshot instanceof PnCounterSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let $ = $pn_counter_kernel.p2p_merge(kernel, other);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new PnCounterState(kernel$1),
          $list.map(events, (var0) => { return new PnCounterEvent(var0); }),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof GCounterState) {
    if (snapshot instanceof GCounterSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let $ = $g_counter_kernel.p2p_merge(kernel, other);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new GCounterState(kernel$1),
          $list.map(events, (var0) => { return new GCounterEvent(var0); }),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof LwwRegisterState) {
    if (snapshot instanceof LwwRegisterSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let _pipe = $lww_register_kernel.p2p_merge(kernel, other);
      let _pipe$1 = $result.map(
        _pipe,
        (pair) => {
          return [
            new LwwRegisterState(pair[0]),
            $list.map(pair[1], (var0) => { return new LwwRegisterEvent(var0); }),
          ];
        },
      );
      return $result.map_error(
        _pipe$1,
        (error) => {
          return new CorruptRemoteOperation(lww_register_error_detail(error));
        },
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof LwwMapState) {
    if (snapshot instanceof LwwMapSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let _pipe = $lww_map_kernel.p2p_merge(kernel, other);
      let _pipe$1 = $result.map(
        _pipe,
        (pair) => {
          return [
            new LwwMapState(pair[0]),
            $list.map(pair[1], (var0) => { return new LwwMapEvent(var0); }),
          ];
        },
      );
      return $result.map_error(
        _pipe$1,
        (error) => {
          return new CorruptRemoteOperation(lww_map_error_detail(error));
        },
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof MvRegisterState) {
    if (snapshot instanceof MvRegisterSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let $ = $mv_register_kernel.p2p_merge(kernel, other);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new MvRegisterState(kernel$1),
          $list.map(events, (var0) => { return new MvRegisterEvent(var0); }),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof OrMapState) {
    if (snapshot instanceof OrMapSnapshot) {
      let kernel = state[0];
      let mode = snapshot.mode;
      let other = snapshot.state;
      let $ = isEqual(kernel.mode, mode);
      if ($) {
        let $1 = $or_map_kernel.p2p_merge(kernel, other);
        if ($1 instanceof Ok) {
          let kernel$1 = $1[0][0];
          let events = $1[0][1];
          return new Ok(
            [
              new OrMapState(kernel$1),
              $list.map(events, (var0) => { return new OrMapEvent(var0); }),
            ],
          );
        } else {
          let error = $1[0];
          return new Error(or_map_p2p_error(error));
        }
      } else {
        return new Error(new UnsupportedP2p("OR-map snapshot mode mismatch"));
      }
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof OrSetState) {
    if (snapshot instanceof OrSetSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let $ = $or_set_kernel.p2p_merge(kernel, other);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new OrSetState(kernel$1),
          $list.map(events, (var0) => { return new OrSetEvent(var0); }),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof GSetState) {
    if (snapshot instanceof GSetSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let $ = $g_set_kernel.p2p_merge(kernel, other);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new GSetState(kernel$1),
          $list.map(events, (var0) => { return new GSetEvent(var0); }),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof TwoPSetState) {
    if (snapshot instanceof TwoPSetSnapshot) {
      let kernel = state[0];
      let other = snapshot.state;
      let $ = $two_p_set_kernel.p2p_merge(kernel, other);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new TwoPSetState(kernel$1),
          $list.map(events, (var0) => { return new TwoPSetEvent(var0); }),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof RegisterCollectionState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof ClaimsState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof TaskManagerState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof PactMapState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof JsonOtState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof DirectoryState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof OrderedCollectionState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (state instanceof SequenceState) {
    if (snapshot instanceof SequenceSummary) {
      let kernel = state[0];
      let other = snapshot.state;
      let $ = $sequence_kernel.p2p_merge(kernel, other);
      let kernel$1 = $[0];
      let events = $[1];
      return new Ok(
        [
          new SequenceState(kernel$1),
          $list.map(events, (var0) => { return new SequenceEvent(var0); }),
        ],
      );
    } else {
      return new Error(unsupported_p2p(state, "remote p2p snapshot"));
    }
  } else if (state instanceof RichTextState) {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  } else if (snapshot instanceof TextSummary) {
    let kernel = state[0];
    let other = snapshot.state;
    let $ = $text_kernel.p2p_merge(kernel, other);
    let kernel$1 = $[0];
    let events = $[1];
    return new Ok(
      [
        new TextState(kernel$1),
        $list.map(events, (var0) => { return new TextEvent(var0); }),
      ],
    );
  } else {
    return new Error(unsupported_p2p(state, "remote p2p snapshot"));
  }
}

/**
 * Take an operation that the kernel released onto the wire while it processed
 * an ack. That operation comes from the one-operation-in-flight buffer
 * promotion of json0. A json0 channel produces such an operation. Every other
 * channel returns `None`.
 */
export function take_outbound(state) {
  if (state instanceof MapState) {
    return [state, Option$None$const];
  } else if (state instanceof CounterState) {
    return [state, Option$None$const];
  } else if (state instanceof PnCounterState) {
    return [state, Option$None$const];
  } else if (state instanceof GCounterState) {
    return [state, Option$None$const];
  } else if (state instanceof LwwRegisterState) {
    return [state, Option$None$const];
  } else if (state instanceof LwwMapState) {
    return [state, Option$None$const];
  } else if (state instanceof MvRegisterState) {
    return [state, Option$None$const];
  } else if (state instanceof OrMapState) {
    return [state, Option$None$const];
  } else if (state instanceof OrSetState) {
    return [state, Option$None$const];
  } else if (state instanceof GSetState) {
    return [state, Option$None$const];
  } else if (state instanceof TwoPSetState) {
    return [state, Option$None$const];
  } else if (state instanceof RegisterCollectionState) {
    return [state, Option$None$const];
  } else if (state instanceof ClaimsState) {
    return [state, Option$None$const];
  } else if (state instanceof TaskManagerState) {
    return [state, Option$None$const];
  } else if (state instanceof PactMapState) {
    return [state, Option$None$const];
  } else if (state instanceof JsonOtState) {
    let kernel = state[0];
    let $ = $json_ot_kernel.take_outbound(kernel);
    let kernel$1 = $[0];
    let out = $[1];
    return [
      new JsonOtState(kernel$1),
      $option.map(out, (var0) => { return new JsonOtOperation(var0); }),
    ];
  } else if (state instanceof DirectoryState) {
    return [state, Option$None$const];
  } else if (state instanceof OrderedCollectionState) {
    return [state, Option$None$const];
  } else if (state instanceof SequenceState) {
    return [state, Option$None$const];
  } else if (state instanceof RichTextState) {
    let kernel = state[0];
    let $ = $rich_text_kernel.take_outbound(kernel);
    let kernel$1 = $[0];
    let out = $[1];
    return [
      new RichTextState(kernel$1),
      $option.map(out, (var0) => { return new RichTextOperation(var0); }),
    ];
  } else {
    return [state, Option$None$const];
  }
}

function same_text_delta(ours, echoed) {
  return $wire.json_semantically_equal(
    $text.to_json(ours),
    $text.to_json(echoed),
  );
}

/**
 * Whether two text operations carry the same diagnostic shape, which is the
 * index intent and the value intent, *and* the same authoritative CRDT delta.
 * The behaviour is the same as in `same_sequence_shape`.
 *
 * The diagnostic fields alone would let a corrupt or changed delta pass the
 * check on the FIFO ack matching. The comparison of the delta keeps that
 * detection. It also treats a delta from a correct reconnect and resubmit as
 * equal, because that delta encodes to the same canonical JSON.
 * 
 * @ignore
 */
function same_text_shape(ours, echoed) {
  if (ours instanceof $text_kernel.Insert) {
    if (echoed instanceof $text_kernel.Insert) {
      let i = ours.index;
      let value = ours.value;
      let delta = ours.delta;
      let i2 = echoed.index;
      let value2 = echoed.value;
      let delta2 = echoed.delta;
      return ((i === i2) && (value === value2)) && same_text_delta(
        delta,
        delta2,
      );
    } else {
      return false;
    }
  } else if (ours instanceof $text_kernel.DeleteRange) {
    if (echoed instanceof $text_kernel.DeleteRange) {
      let s = ours.start;
      let e = ours.end;
      let delta = ours.delta;
      let s2 = echoed.start;
      let e2 = echoed.end;
      let delta2 = echoed.delta;
      return ((s === s2) && (e === e2)) && same_text_delta(delta, delta2);
    } else {
      return false;
    }
  } else if (ours instanceof $text_kernel.ReplaceRange) {
    if (echoed instanceof $text_kernel.ReplaceRange) {
      let s = ours.start;
      let e = ours.end;
      let value = ours.value;
      let delta = ours.delta;
      let s2 = echoed.start;
      let e2 = echoed.end;
      let value2 = echoed.value;
      let delta2 = echoed.delta;
      return (((s === s2) && (e === e2)) && (value === value2)) && same_text_delta(
        delta,
        delta2,
      );
    } else {
      return false;
    }
  } else if (echoed instanceof $text_kernel.Append) {
    let value = ours.value;
    let delta = ours.delta;
    let value2 = echoed.value;
    let delta2 = echoed.delta;
    return (value === value2) && same_text_delta(delta, delta2);
  } else {
    return false;
  }
}

function same_sequence_delta(ours, echoed) {
  return $wire.json_semantically_equal(
    $sequence.to_json(ours, (value) => { return value; }),
    $sequence.to_json(echoed, (value) => { return value; }),
  );
}

function same_json_value(ours, echoed) {
  return $wire.json_semantically_equal(ours, echoed);
}

function same_sequence_shape(ours, echoed) {
  if (ours instanceof $sequence_kernel.Insert) {
    if (echoed instanceof $sequence_kernel.Insert) {
      let i = ours.index;
      let value = ours.value;
      let delta = ours.delta;
      let i2 = echoed.index;
      let value2 = echoed.value;
      let delta2 = echoed.delta;
      return ((i === i2) && same_json_value(value, value2)) && same_sequence_delta(
        delta,
        delta2,
      );
    } else {
      return false;
    }
  } else if (ours instanceof $sequence_kernel.Delete) {
    if (echoed instanceof $sequence_kernel.Delete) {
      let i = ours.index;
      let delta = ours.delta;
      let i2 = echoed.index;
      let delta2 = echoed.delta;
      return (i === i2) && same_sequence_delta(delta, delta2);
    } else {
      return false;
    }
  } else if (ours instanceof $sequence_kernel.Move) {
    if (echoed instanceof $sequence_kernel.Move) {
      let from = ours.from_index;
      let to = ours.to_index;
      let delta = ours.delta;
      let from2 = echoed.from_index;
      let to2 = echoed.to_index;
      let delta2 = echoed.delta;
      return ((from === from2) && (to === to2)) && same_sequence_delta(
        delta,
        delta2,
      );
    } else {
      return false;
    }
  } else if (echoed instanceof $sequence_kernel.Replace) {
    let i = ours.index;
    let value = ours.value;
    let delta = ours.delta;
    let i2 = echoed.index;
    let value2 = echoed.value;
    let delta2 = echoed.delta;
    return ((i === i2) && same_json_value(value, value2)) && same_sequence_delta(
      delta,
      delta2,
    );
  } else {
    return false;
  }
}

function same_ordered_shape(ours, echoed) {
  if (ours instanceof $ordered_collection_kernel.Add) {
    if (echoed instanceof $ordered_collection_kernel.Add) {
      let our_value = ours.value;
      let echoed_value = echoed.value;
      return same_json_value(our_value, echoed_value);
    } else {
      return false;
    }
  } else if (ours instanceof $ordered_collection_kernel.Acquire) {
    if (echoed instanceof $ordered_collection_kernel.Acquire) {
      let our_id = ours.acquire_id;
      let echoed_id = echoed.acquire_id;
      return our_id === echoed_id;
    } else {
      return false;
    }
  } else if (ours instanceof $ordered_collection_kernel.Complete) {
    if (echoed instanceof $ordered_collection_kernel.Complete) {
      let our_id = ours.acquire_id;
      let echoed_id = echoed.acquire_id;
      return our_id === echoed_id;
    } else {
      return false;
    }
  } else if (echoed instanceof $ordered_collection_kernel.Release) {
    let our_id = ours.acquire_id;
    let echoed_id = echoed.acquire_id;
    return our_id === echoed_id;
  } else {
    return false;
  }
}

function same_directory_shape(ours, echoed) {
  if (ours instanceof $directory_kernel.Set) {
    if (echoed instanceof $directory_kernel.Set) {
      let p = ours.path;
      let k = ours.key;
      let p2 = echoed.path;
      let k2 = echoed.key;
      return (p === p2) && (k === k2);
    } else {
      return false;
    }
  } else if (ours instanceof $directory_kernel.Delete) {
    if (echoed instanceof $directory_kernel.Delete) {
      let p = ours.path;
      let k = ours.key;
      let p2 = echoed.path;
      let k2 = echoed.key;
      return (p === p2) && (k === k2);
    } else {
      return false;
    }
  } else if (ours instanceof $directory_kernel.Clear) {
    if (echoed instanceof $directory_kernel.Clear) {
      let p = ours.path;
      let p2 = echoed.path;
      return p === p2;
    } else {
      return false;
    }
  } else if (ours instanceof $directory_kernel.CreateSubDirectory) {
    if (echoed instanceof $directory_kernel.CreateSubDirectory) {
      let p = ours.path;
      let n = ours.name;
      let p2 = echoed.path;
      let n2 = echoed.name;
      return (p === p2) && (n === n2);
    } else {
      return false;
    }
  } else if (echoed instanceof $directory_kernel.DeleteSubDirectory) {
    let p = ours.path;
    let n = ours.name;
    let p2 = echoed.path;
    let n2 = echoed.name;
    return (p === p2) && (n === n2);
  } else {
    return false;
  }
}

/**
 * A PactMap value is an `Option(Json)` value. `None` is a true tombstone,
 * which is not the same as `Some(null)`. It thus gets its own `Absent` wire
 * tag, and not a JSON `null`.
 * 
 * @ignore
 */
function encode_optional_value(value) {
  if (value instanceof Some) {
    let inner = value[0];
    return $json.object(
      toList([["type", $json.string("Plain")], ["value", inner]]),
    );
  } else {
    return $json.object(toList([["type", $json.string("Absent")]]));
  }
}

function same_optional_json(a, b) {
  return $json.to_string(encode_optional_value(a)) === $json.to_string(
    encode_optional_value(b),
  );
}

function same_pact_map_shape(ours, echoed) {
  if (ours instanceof $pact_map_kernel.Set) {
    if (echoed instanceof $pact_map_kernel.Set) {
      let our_key = ours.key;
      let our_value = ours.value;
      let our_reference = ours.reference_sequence_number;
      let echoed_key = echoed.key;
      let echoed_value = echoed.value;
      let echoed_reference = echoed.reference_sequence_number;
      return ((our_key === echoed_key) && same_optional_json(
        our_value,
        echoed_value,
      )) && (our_reference === echoed_reference);
    } else {
      return false;
    }
  } else if (echoed instanceof $pact_map_kernel.Accept) {
    let our_key = ours.key;
    let echoed_key = echoed.key;
    return our_key === echoed_key;
  } else {
    return false;
  }
}

function same_task_manager_shape(ours, echoed) {
  if (ours instanceof $task_manager_kernel.Volunteer) {
    if (echoed instanceof $task_manager_kernel.Volunteer) {
      let our_task = ours.task_id;
      let echoed_task = echoed.task_id;
      return our_task === echoed_task;
    } else {
      return false;
    }
  } else if (ours instanceof $task_manager_kernel.Abandon) {
    if (echoed instanceof $task_manager_kernel.Abandon) {
      let our_task = ours.task_id;
      let echoed_task = echoed.task_id;
      return our_task === echoed_task;
    } else {
      return false;
    }
  } else if (echoed instanceof $task_manager_kernel.Complete) {
    let our_task = ours.task_id;
    let echoed_task = echoed.task_id;
    return our_task === echoed_task;
  } else {
    return false;
  }
}

function same_two_p_set_shape(ours, echoed) {
  if (ours instanceof $two_p_set_kernel.Add) {
    if (echoed instanceof $two_p_set_kernel.Add) {
      let our_element = ours.element;
      let echoed_element = echoed.element;
      return our_element === echoed_element;
    } else {
      return false;
    }
  } else if (echoed instanceof $two_p_set_kernel.Remove) {
    let our_element = ours.element;
    let echoed_element = echoed.element;
    return our_element === echoed_element;
  } else {
    return false;
  }
}

function same_g_set_shape(ours, echoed) {
  let our_element = ours.element;
  let echoed_element = echoed.element;
  return our_element === echoed_element;
}

function same_or_set_shape(ours, echoed) {
  if (ours instanceof $or_set_kernel.Add) {
    if (echoed instanceof $or_set_kernel.Add) {
      let our_element = ours.element;
      let echoed_element = echoed.element;
      return our_element === echoed_element;
    } else {
      return false;
    }
  } else if (echoed instanceof $or_set_kernel.Remove) {
    let our_element = ours.element;
    let echoed_element = echoed.element;
    return our_element === echoed_element;
  } else {
    return false;
  }
}

function same_or_map_shape(ours, echoed) {
  if (ours instanceof $or_map_kernel.Increment) {
    if (echoed instanceof $or_map_kernel.Increment) {
      let our_key = ours.key;
      let our_amount = ours.amount;
      let echoed_key = echoed.key;
      let echoed_amount = echoed.amount;
      return (our_key === echoed_key) && (our_amount === echoed_amount);
    } else {
      return false;
    }
  } else if (ours instanceof $or_map_kernel.SetRegister) {
    if (echoed instanceof $or_map_kernel.SetRegister) {
      let our_key = ours.key;
      let our_value = ours.value;
      let our_ts = ours.timestamp;
      let echoed_key = echoed.key;
      let echoed_value = echoed.value;
      let echoed_ts = echoed.timestamp;
      return ((our_key === echoed_key) && (our_value === echoed_value)) && (our_ts === echoed_ts);
    } else {
      return false;
    }
  } else if (ours instanceof $or_map_kernel.SetMvRegister) {
    if (echoed instanceof $or_map_kernel.SetMvRegister) {
      let our_key = ours.key;
      let our_value = ours.value;
      let echoed_key = echoed.key;
      let echoed_value = echoed.value;
      return (our_key === echoed_key) && (our_value === echoed_value);
    } else {
      return false;
    }
  } else if (ours instanceof $or_map_kernel.Remove) {
    if (echoed instanceof $or_map_kernel.Remove) {
      let our_key = ours.key;
      let echoed_key = echoed.key;
      return our_key === echoed_key;
    } else {
      return false;
    }
  } else if (ours instanceof $or_map_kernel.AddMember) {
    if (echoed instanceof $or_map_kernel.AddMember) {
      let our_key = ours.key;
      let our_member = ours.member;
      let echoed_key = echoed.key;
      let echoed_member = echoed.member;
      return (our_key === echoed_key) && (our_member === echoed_member);
    } else {
      return false;
    }
  } else if (echoed instanceof $or_map_kernel.RemoveMember) {
    let our_key = ours.key;
    let our_member = ours.member;
    let echoed_key = echoed.key;
    let echoed_member = echoed.member;
    return (our_key === echoed_key) && (our_member === echoed_member);
  } else {
    return false;
  }
}

function same_map_shape(ours, echoed) {
  if (ours instanceof $map_kernel.Set) {
    if (echoed instanceof $map_kernel.Set) {
      let our_key = ours.key;
      let echoed_key = echoed.key;
      return our_key === echoed_key;
    } else {
      return false;
    }
  } else if (ours instanceof $map_kernel.Delete) {
    if (echoed instanceof $map_kernel.Delete) {
      let our_key = ours.key;
      let echoed_key = echoed.key;
      return our_key === echoed_key;
    } else {
      return false;
    }
  } else if (echoed instanceof $map_kernel.Clear) {
    return true;
  } else {
    return false;
  }
}

/**
 * Whether the sequenced echo of a local operation has the shape that this
 * client submitted. This is the check on the FIFO ack matching.
 */
export function same_shape(ours, echoed) {
  if (ours instanceof MapOperation) {
    if (echoed instanceof MapOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_map_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof CounterOperation) {
    if (echoed instanceof CounterOperation) {
      let ours$1 = ours[0].increment_amount;
      let echoed$1 = echoed[0].increment_amount;
      return ours$1 === echoed$1;
    } else {
      return false;
    }
  } else if (ours instanceof PnCounterOperation) {
    if (echoed instanceof PnCounterOperation) {
      let our_amount = ours[0].amount;
      let our_delta = ours[0].delta;
      let echoed_amount = echoed[0].amount;
      let echoed_delta = echoed[0].delta;
      return (our_amount === echoed_amount) && (isEqual(our_delta, echoed_delta));
    } else {
      return false;
    }
  } else if (ours instanceof GCounterOperation) {
    if (echoed instanceof GCounterOperation) {
      let our_amount = ours[0].amount;
      let our_delta = ours[0].delta;
      let echoed_amount = echoed[0].amount;
      let echoed_delta = echoed[0].delta;
      return (our_amount === echoed_amount) && (isEqual(our_delta, echoed_delta));
    } else {
      return false;
    }
  } else if (ours instanceof LwwRegisterOperation) {
    if (echoed instanceof LwwRegisterOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof LwwMapOperation) {
    if (echoed instanceof LwwMapOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof MvRegisterOperation) {
    if (echoed instanceof MvRegisterOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof OrMapOperation) {
    if (echoed instanceof OrMapOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_or_map_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof OrSetOperation) {
    if (echoed instanceof OrSetOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_or_set_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof GSetOperation) {
    if (echoed instanceof GSetOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_g_set_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof TwoPSetOperation) {
    if (echoed instanceof TwoPSetOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_two_p_set_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof RegisterCollectionOperation) {
    if (echoed instanceof RegisterCollectionOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return ((ours$1.key === echoed$1.key) && (isEqual(
        ours$1.value,
        echoed$1.value
      ))) && (ours$1.reference_sequence_number === echoed$1.reference_sequence_number);
    } else {
      return false;
    }
  } else if (ours instanceof ClaimsOperation) {
    if (echoed instanceof ClaimsOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return ((ours$1.key === echoed$1.key) && (isEqual(
        ours$1.value,
        echoed$1.value
      ))) && (ours$1.reference_sequence_number === echoed$1.reference_sequence_number);
    } else {
      return false;
    }
  } else if (ours instanceof TaskManagerOperation) {
    if (echoed instanceof TaskManagerOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_task_manager_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof PactMapOperation) {
    if (echoed instanceof PactMapOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_pact_map_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof JsonOtOperation) {
    if (echoed instanceof JsonOtOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return (ours$1.reference_sequence_number === echoed$1.reference_sequence_number) && (isEqual(
        ours$1.components,
        echoed$1.components
      ));
    } else {
      return false;
    }
  } else if (ours instanceof DirectoryOperation) {
    if (echoed instanceof DirectoryOperation) {
      let ours$1 = ours.operation;
      let our_id = ours.message_id;
      let echoed$1 = echoed.operation;
      let echoed_id = echoed.message_id;
      return (our_id === echoed_id) && same_directory_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof OrderedCollectionOperation) {
    if (echoed instanceof OrderedCollectionOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_ordered_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof SequenceOperation) {
    if (echoed instanceof SequenceOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return same_sequence_shape(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof RichTextOperation) {
    if (echoed instanceof RichTextOperation) {
      let ours$1 = ours[0];
      let echoed$1 = echoed[0];
      return (ours$1.reference_sequence_number === echoed$1.reference_sequence_number) && (isEqual(
        ours$1.delta,
        echoed$1.delta
      ));
    } else {
      return false;
    }
  } else if (echoed instanceof TextOperation) {
    let ours$1 = ours[0];
    let echoed$1 = echoed[0];
    return same_text_shape(ours$1, echoed$1);
  } else {
    return false;
  }
}

/**
 * `{queue: [value...], jobs: [{acquireId, value, owner}]}`. `owner` is an
 * integer client id, or `null` for a job that a local client acquired while
 * the collection was unattached.
 * 
 * @ignore
 */
function encode_ordered_snapshot(queue, jobs) {
  return $json.object(
    toList([
      ["queue", $json.preprocessed_array(queue)],
      [
        "jobs",
        $json.array(
          jobs,
          (entry) => {
            let acquire_id;
            let value;
            let owner;
            acquire_id = entry[0];
            value = entry[1].value;
            owner = entry[1].owner;
            return $json.object(
              toList([
                ["acquireId", $json.string(acquire_id)],
                ["value", value],
                [
                  "owner",
                  (() => {
                    if (owner instanceof Some) {
                      let id = owner[0];
                      return $json.int(id);
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
  );
}

function encode_create_info(create) {
  return $json.object(
    toList([
      ["seq", $json.int(create.sequence_number)],
      ["clientSeq", $json.int(create.client_sequence_number)],
    ]),
  );
}

/**
 * The recursive JSON of a directory summary. Each node carries its ordered
 * storage entries, its create info, its creator ids, its detached flag, and
 * its named child directories, in directory order.
 * 
 * @ignore
 */
function encode_directory_summary(summary) {
  return $json.object(
    toList([
      ["storage", $wire.encode_entries(summary.storage)],
      ["create", encode_create_info(summary.create)],
      ["creators", $json.array(summary.creators, $json.int)],
      ["detachedCreated", $json.bool(summary.detached_created)],
      [
        "subdirs",
        $json.array(
          summary.subdirectories,
          (entry) => {
            return $json.object(
              toList([
                ["name", $json.string(entry[0])],
                ["dir", encode_directory_summary(entry[1])],
              ]),
            );
          },
        ),
      ],
    ]),
  );
}

function encode_pact(pact) {
  let accepted = pact.accepted;
  let pending = pact.pending;
  return $json.object(
    toList([
      [
        "accepted",
        (() => {
          if (accepted instanceof Some) {
            let value = accepted[0].value;
            let sequence_number = accepted[0].sequence_number;
            return $json.object(
              toList([
                ["value", encode_optional_value(value)],
                ["sequenceNumber", $json.int(sequence_number)],
              ]),
            );
          } else {
            return $json.null$();
          }
        })(),
      ],
      [
        "pending",
        (() => {
          if (pending instanceof Some) {
            let value = pending[0].value;
            let signoffs = pending[0].expected_signoffs;
            return $json.object(
              toList([
                ["value", encode_optional_value(value)],
                ["expectedSignoffs", $json.array(signoffs, $json.int)],
              ]),
            );
          } else {
            return $json.null$();
          }
        })(),
      ],
    ]),
  );
}

function encode_pact_entries(entries) {
  return $json.array(
    entries,
    (entry) => {
      let key = entry[0];
      let pact = entry[1];
      return $json.object(
        toList([["key", $json.string(key)], ["pact", encode_pact(pact)]]),
      );
    },
  );
}

function same_entries(ours, echoed) {
  if (ours instanceof $Empty) {
    if (echoed instanceof $Empty) {
      return true;
    } else {
      return false;
    }
  } else if (echoed instanceof $Empty) {
    return false;
  } else {
    let our = ours.head;
    let our_rest = ours.tail;
    let echoed$1 = echoed.head;
    let echoed_rest = echoed.tail;
    return ((our[0] === echoed$1[0]) && same_json_value(our[1], echoed$1[1])) && same_entries(
      our_rest,
      echoed_rest,
    );
  }
}

/**
 * Whether the sequenced echo of a local attach carries the snapshot that this
 * client submitted. The function compares the values by structure, and not by
 * their bytes.
 */
export function same_snapshot(ours, echoed) {
  if (ours instanceof MapSnapshot) {
    if (echoed instanceof MapSnapshot) {
      let ours$1 = ours.entries;
      let echoed$1 = echoed.entries;
      return same_entries(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof CounterSnapshot) {
    if (echoed instanceof CounterSnapshot) {
      let ours$1 = ours.value;
      let echoed$1 = echoed.value;
      return ours$1 === echoed$1;
    } else {
      return false;
    }
  } else if (ours instanceof PnCounterSnapshot) {
    if (echoed instanceof PnCounterSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof GCounterSnapshot) {
    if (echoed instanceof GCounterSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof LwwRegisterSnapshot) {
    if (echoed instanceof LwwRegisterSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof LwwMapSnapshot) {
    if (echoed instanceof LwwMapSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof MvRegisterSnapshot) {
    if (echoed instanceof MvRegisterSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof OrMapSnapshot) {
    if (echoed instanceof OrMapSnapshot) {
      let our_mode = ours.mode;
      let ours$1 = ours.state;
      let echoed_mode = echoed.mode;
      let echoed$1 = echoed.state;
      return (isEqual(our_mode, echoed_mode)) && (isEqual(ours$1, echoed$1));
    } else {
      return false;
    }
  } else if (ours instanceof OrSetSnapshot) {
    if (echoed instanceof OrSetSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof GSetSnapshot) {
    if (echoed instanceof GSetSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof TwoPSetSnapshot) {
    if (echoed instanceof TwoPSetSnapshot) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof RegisterCollectionSnapshot) {
    if (echoed instanceof RegisterCollectionSnapshot) {
      let ours$1 = ours.registers;
      let echoed$1 = echoed.registers;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof ClaimsSnapshot) {
    if (echoed instanceof ClaimsSnapshot) {
      let ours$1 = ours.entries;
      let echoed$1 = echoed.entries;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof TaskManagerSnapshot) {
    if (echoed instanceof TaskManagerSnapshot) {
      let ours$1 = ours.queues;
      let echoed$1 = echoed.queues;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof PactMapSnapshot) {
    if (echoed instanceof PactMapSnapshot) {
      let ours$1 = ours.entries;
      let echoed$1 = echoed.entries;
      return $json.to_string(encode_pact_entries(ours$1)) === $json.to_string(
        encode_pact_entries(echoed$1),
      );
    } else {
      return false;
    }
  } else if (ours instanceof JsonOtSnapshot) {
    if (echoed instanceof JsonOtSnapshot) {
      let ours$1 = ours.document;
      let echoed$1 = echoed.document;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (ours instanceof DirectorySnapshot) {
    if (echoed instanceof DirectorySnapshot) {
      let ours$1 = ours.summary;
      let echoed$1 = echoed.summary;
      return $json.to_string(encode_directory_summary(ours$1)) === $json.to_string(
        encode_directory_summary(echoed$1),
      );
    } else {
      return false;
    }
  } else if (ours instanceof OrderedCollectionSnapshot) {
    if (echoed instanceof OrderedCollectionSnapshot) {
      let our_queue = ours.queue;
      let our_jobs = ours.jobs;
      let echoed_queue = echoed.queue;
      let echoed_jobs = echoed.jobs;
      return $json.to_string(encode_ordered_snapshot(our_queue, our_jobs)) === $json.to_string(
        encode_ordered_snapshot(echoed_queue, echoed_jobs),
      );
    } else {
      return false;
    }
  } else if (ours instanceof SequenceSummary) {
    if (echoed instanceof SequenceSummary) {
      let ours$1 = ours.state;
      let echoed$1 = echoed.state;
      return same_json_value(
        $sequence.to_json(ours$1, (value) => { return value; }),
        $sequence.to_json(echoed$1, (value) => { return value; }),
      );
    } else {
      return false;
    }
  } else if (ours instanceof RichTextSnapshot) {
    if (echoed instanceof RichTextSnapshot) {
      let ours$1 = ours.document;
      let echoed$1 = echoed.document;
      return isEqual(ours$1, echoed$1);
    } else {
      return false;
    }
  } else if (echoed instanceof TextSummary) {
    let ours$1 = ours.state;
    let echoed$1 = echoed.state;
    return same_json_value($text.to_json(ours$1), $text.to_json(echoed$1));
  } else {
    return false;
  }
}

/**
 * The handle addresses that the current values of the channel reach, for the
 * order of the attach dependencies. A counter holds no handle.
 */
export function handle_addresses(state) {
  if (state instanceof MapState) {
    let kernel = state[0];
    let _pipe = $list.flat_map(
      $map_kernel.entries(kernel),
      (entry) => { return $handle.collect_handle_addresses(entry[1]); },
    );
    return $list.unique(_pipe);
  } else if (state instanceof CounterState) {
    return $List$Empty$const;
  } else if (state instanceof PnCounterState) {
    return $List$Empty$const;
  } else if (state instanceof GCounterState) {
    return $List$Empty$const;
  } else if (state instanceof LwwRegisterState) {
    return $List$Empty$const;
  } else if (state instanceof LwwMapState) {
    return $List$Empty$const;
  } else if (state instanceof MvRegisterState) {
    return $List$Empty$const;
  } else if (state instanceof OrMapState) {
    let kernel = state[0];
    let $ = kernel.mode;
    if ($ instanceof $or_map_kernel.TallyMode) {
      return $List$Empty$const;
    } else if ($ instanceof $or_map_kernel.RegisterMode) {
      let _pipe = $list.flat_map(
        $or_map_kernel.entries(kernel),
        (entry) => {
          let $1 = entry[1];
          if ($1 instanceof $or_map_kernel.Tally) {
            return $List$Empty$const;
          } else if ($1 instanceof $or_map_kernel.Register) {
            let raw = $1[0];
            let $2 = $json.parse(raw, $wire.json_value_decoder());
            if ($2 instanceof Ok) {
              let value = $2[0];
              return $handle.collect_handle_addresses(value);
            } else {
              return $List$Empty$const;
            }
          } else if ($1 instanceof $or_map_kernel.SetMembers) {
            return $List$Empty$const;
          } else {
            return $List$Empty$const;
          }
        },
      );
      return $list.unique(_pipe);
    } else if ($ instanceof $or_map_kernel.OrSetMode) {
      return $List$Empty$const;
    } else {
      return $List$Empty$const;
    }
  } else if (state instanceof OrSetState) {
    return $List$Empty$const;
  } else if (state instanceof GSetState) {
    return $List$Empty$const;
  } else if (state instanceof TwoPSetState) {
    return $List$Empty$const;
  } else if (state instanceof RegisterCollectionState) {
    let kernel = state[0];
    let _pipe = $list.flat_map(
      $register_collection_kernel.summary_registers(kernel),
      (entry) => {
        let atomic;
        let versions;
        atomic = entry[1].atomic;
        versions = entry[1].versions;
        let _pipe = listPrepend(atomic, versions);
        return $list.flat_map(
          _pipe,
          (version) => {
            return $handle.collect_handle_addresses(version.value);
          },
        );
      },
    );
    return $list.unique(_pipe);
  } else if (state instanceof ClaimsState) {
    let kernel = state[0];
    let _pipe = $list.append(
      (() => {
        let _pipe = $claims_kernel.summary_entries(kernel);
        return $list.flat_map(
          _pipe,
          (entry) => { return $handle.collect_handle_addresses(entry[1]); },
        );
      })(),
      (() => {
        let _pipe = $claims_kernel.pending_values(kernel);
        return $list.flat_map(_pipe, $handle.collect_handle_addresses);
      })(),
    );
    return $list.unique(_pipe);
  } else if (state instanceof TaskManagerState) {
    return $List$Empty$const;
  } else if (state instanceof PactMapState) {
    return $List$Empty$const;
  } else if (state instanceof JsonOtState) {
    return $List$Empty$const;
  } else if (state instanceof DirectoryState) {
    return $List$Empty$const;
  } else if (state instanceof OrderedCollectionState) {
    let kernel = state[0];
    let _pipe = $list.append(
      $ordered_collection_kernel.summary_queue(kernel),
      $list.map(
        $ordered_collection_kernel.summary_jobs(kernel),
        (entry) => {
          let value;
          value = entry[1].value;
          return value;
        },
      ),
    );
    let _pipe$1 = $list.flat_map(_pipe, $handle.collect_handle_addresses);
    return $list.unique(_pipe$1);
  } else if (state instanceof SequenceState) {
    let kernel = state[0];
    let _pipe = $sequence_kernel.values(kernel);
    let _pipe$1 = $list.flat_map(_pipe, $handle.collect_handle_addresses);
    return $list.unique(_pipe$1);
  } else if (state instanceof RichTextState) {
    let kernel = state[0];
    let _block;
    let $ = $rich_text_kernel.view(kernel);
    if ($ instanceof Ok) {
      let document = $[0];
      _block = document;
    } else {
      _block = $rich_text_kernel.summary(kernel);
    }
    let document = _block;
    return $handle.collect_handle_addresses(
      $rich_text.document_to_json(document),
    );
  } else {
    return $List$Empty$const;
  }
}

function encode_task_queues(queues) {
  return $json.array(
    queues,
    (entry) => {
      let task_id = entry[0];
      let queue = entry[1];
      return $json.object(
        toList([
          ["taskId", $json.string(task_id)],
          ["queue", $json.array(queue, $json.int)],
        ]),
      );
    },
  );
}

function encode_claims(entries) {
  return $json.array(
    entries,
    (entry) => {
      let key = entry[0];
      let value = entry[1];
      let sequence_number = entry[2];
      return $json.object(
        toList([
          ["key", $json.string(key)],
          ["value", value],
          ["sequenceNumber", $json.int(sequence_number)],
        ]),
      );
    },
  );
}

function encode_versioned(version) {
  return $json.object(
    toList([
      ["value", version.value],
      ["sequenceNumber", $json.int(version.sequence_number)],
    ]),
  );
}

function encode_registers(registers) {
  return $json.array(
    registers,
    (entry) => {
      let key;
      let atomic;
      let versions;
      key = entry[0];
      atomic = entry[1].atomic;
      versions = entry[1].versions;
      return $json.object(
        toList([
          ["key", $json.string(key)],
          ["atomic", encode_versioned(atomic)],
          ["versions", $json.array(versions, encode_versioned)],
        ]),
      );
    },
  );
}

/**
 * Encode the payload of a snapshot, whose shape depends on the channel type.
 * That payload is the `snapshot` field of the attach operation, and the `data`
 * field of the channel in the summary blob.
 */
export function encode_snapshot(snapshot) {
  if (snapshot instanceof MapSnapshot) {
    let entries = snapshot.entries;
    return $wire.encode_entries(entries);
  } else if (snapshot instanceof CounterSnapshot) {
    let value = snapshot.value;
    return $json.int(value);
  } else if (snapshot instanceof PnCounterSnapshot) {
    let state = snapshot.state;
    return $pn_counter.to_json(state);
  } else if (snapshot instanceof GCounterSnapshot) {
    let state = snapshot.state;
    return $g_counter.to_json(state);
  } else if (snapshot instanceof LwwRegisterSnapshot) {
    let state = snapshot.state;
    return $lww_register.to_json(state);
  } else if (snapshot instanceof LwwMapSnapshot) {
    let state = snapshot.state;
    return $lww_map.to_json(state);
  } else if (snapshot instanceof MvRegisterSnapshot) {
    let state = snapshot.state;
    return $mv_register.to_json(state);
  } else if (snapshot instanceof OrMapSnapshot) {
    let state = snapshot.state;
    return $or_map.to_json(state);
  } else if (snapshot instanceof OrSetSnapshot) {
    let state = snapshot.state;
    return $or_set.to_json(state);
  } else if (snapshot instanceof GSetSnapshot) {
    let state = snapshot.state;
    return $g_set.to_json(state);
  } else if (snapshot instanceof TwoPSetSnapshot) {
    let state = snapshot.state;
    return $two_p_set.to_json(state);
  } else if (snapshot instanceof RegisterCollectionSnapshot) {
    let registers = snapshot.registers;
    return encode_registers(registers);
  } else if (snapshot instanceof ClaimsSnapshot) {
    let entries = snapshot.entries;
    return encode_claims(entries);
  } else if (snapshot instanceof TaskManagerSnapshot) {
    let queues = snapshot.queues;
    return encode_task_queues(queues);
  } else if (snapshot instanceof PactMapSnapshot) {
    let entries = snapshot.entries;
    return encode_pact_entries(entries);
  } else if (snapshot instanceof JsonOtSnapshot) {
    let document = snapshot.document;
    return $json_ot.to_json(document);
  } else if (snapshot instanceof DirectorySnapshot) {
    let summary = snapshot.summary;
    return encode_directory_summary(summary);
  } else if (snapshot instanceof OrderedCollectionSnapshot) {
    let queue = snapshot.queue;
    let jobs = snapshot.jobs;
    return encode_ordered_snapshot(queue, jobs);
  } else if (snapshot instanceof SequenceSummary) {
    let state = snapshot.state;
    return $sequence.to_json(state, (value) => { return value; });
  } else if (snapshot instanceof RichTextSnapshot) {
    let document = snapshot.document;
    return $rich_text.document_to_json(document);
  } else {
    let state = snapshot.state;
    return $text.to_json(state);
  }
}

function text_summary_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      let $ = $text.from_json(encoded);
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new TextSummary(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "TextSummary",
        );
      }
    },
  );
}

function rich_text_snapshot_decoder() {
  return $decode.then$(
    $json_ot.decoder(),
    (value) => {
      let $ = $rich_text.document_from_json(value);
      if ($ instanceof Ok) {
        let document = $[0];
        return $decode.success(new RichTextSnapshot(document));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "RichTextSnapshot",
        );
      }
    },
  );
}

function sequence_summary_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      let $ = $sequence.from_json(encoded, $wire.json_value_decoder());
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new SequenceSummary(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "SequenceSummary",
        );
      }
    },
  );
}

function ordered_job_decoder() {
  return $decode.field(
    "acquireId",
    $decode.string,
    (acquire_id) => {
      return $decode.field(
        "value",
        $wire.json_value_decoder(),
        (value) => {
          return $decode.field(
            "owner",
            $decode.optional($decode.int),
            (owner) => {
              return $decode.success(
                [
                  acquire_id,
                  new $ordered_collection_kernel.JobEntry(value, owner),
                ],
              );
            },
          );
        },
      );
    },
  );
}

function ordered_snapshot_decoder() {
  return $decode.field(
    "queue",
    $decode.list($wire.json_value_decoder()),
    (queue) => {
      return $decode.field(
        "jobs",
        $decode.list(ordered_job_decoder()),
        (jobs) => {
          return $decode.success(new OrderedCollectionSnapshot(queue, jobs));
        },
      );
    },
  );
}

function create_info_decoder() {
  return $decode.field(
    "seq",
    $decode.int,
    (sequence_number) => {
      return $decode.field(
        "clientSeq",
        $decode.int,
        (client_sequence_number) => {
          return $decode.success(
            new $directory_kernel.CreateInfo(
              sequence_number,
              client_sequence_number,
            ),
          );
        },
      );
    },
  );
}

function directory_subdirectory_decoder() {
  return $decode.field(
    "name",
    $decode.string,
    (name) => {
      return $decode.field(
        "dir",
        $decode.recursive(directory_summary_decoder),
        (directory) => { return $decode.success([name, directory]); },
      );
    },
  );
}

function directory_summary_decoder() {
  return $decode.field(
    "storage",
    $decode.list($wire.entry_decoder()),
    (storage) => {
      return $decode.field(
        "create",
        create_info_decoder(),
        (create) => {
          return $decode.field(
            "creators",
            $decode.list($decode.int),
            (creators) => {
              return $decode.field(
                "detachedCreated",
                $decode.bool,
                (detached_created) => {
                  return $decode.field(
                    "subdirs",
                    $decode.list(directory_subdirectory_decoder()),
                    (subdirectories) => {
                      return $decode.success(
                        new $directory_kernel.DirectorySummary(
                          storage,
                          create,
                          creators,
                          detached_created,
                          subdirectories,
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
}

function optional_value_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (value_type) => {
      if (value_type === "Plain") {
        return $decode.field(
          "value",
          $wire.json_value_decoder(),
          (inner) => { return $decode.success(new Some(inner)); },
        );
      } else if (value_type === "Absent") {
        return $decode.success(Option$None$const);
      } else {
        return $decode.failure(Option$None$const, "PactValue");
      }
    },
  );
}

function pending_decoder() {
  return $decode.field(
    "value",
    optional_value_decoder(),
    (value) => {
      return $decode.field(
        "expectedSignoffs",
        $decode.list($decode.int),
        (signoffs) => {
          return $decode.success(new $pact_map_kernel.Pending(value, signoffs));
        },
      );
    },
  );
}

function accepted_decoder() {
  return $decode.field(
    "value",
    optional_value_decoder(),
    (value) => {
      return $decode.field(
        "sequenceNumber",
        $decode.int,
        (sequence_number) => {
          return $decode.success(
            new $pact_map_kernel.Accepted(value, sequence_number),
          );
        },
      );
    },
  );
}

function pact_decoder() {
  return $decode.field(
    "accepted",
    $decode.optional(accepted_decoder()),
    (accepted) => {
      return $decode.field(
        "pending",
        $decode.optional(pending_decoder()),
        (pending) => {
          return $decode.success(new $pact_map_kernel.Pact(accepted, pending));
        },
      );
    },
  );
}

function pact_entry_decoder() {
  return $decode.field(
    "key",
    $decode.string,
    (key) => {
      return $decode.field(
        "pact",
        pact_decoder(),
        (pact) => { return $decode.success([key, pact]); },
      );
    },
  );
}

function task_queue_decoder() {
  return $decode.field(
    "taskId",
    $decode.string,
    (task_id) => {
      return $decode.field(
        "queue",
        $decode.list($decode.int),
        (queue) => { return $decode.success([task_id, queue]); },
      );
    },
  );
}

function claim_entry_decoder() {
  return $decode.field(
    "key",
    $decode.string,
    (key) => {
      return $decode.field(
        "value",
        $wire.json_value_decoder(),
        (value) => {
          return $decode.field(
            "sequenceNumber",
            $decode.int,
            (sequence_number) => {
              return $decode.success([key, value, sequence_number]);
            },
          );
        },
      );
    },
  );
}

function versioned_decoder() {
  return $decode.field(
    "value",
    $wire.json_value_decoder(),
    (value) => {
      return $decode.field(
        "sequenceNumber",
        $decode.int,
        (sequence_number) => {
          return $decode.success(
            new $register_collection_kernel.VersionedValue(
              value,
              sequence_number,
            ),
          );
        },
      );
    },
  );
}

function register_entry_decoder() {
  return $decode.field(
    "key",
    $decode.string,
    (key) => {
      return $decode.field(
        "atomic",
        versioned_decoder(),
        (atomic) => {
          return $decode.field(
            "versions",
            $decode.list(versioned_decoder()),
            (versions) => {
              return $decode.success(
                [
                  key,
                  new $register_collection_kernel.Register(atomic, versions),
                ],
              );
            },
          );
        },
      );
    },
  );
}

function two_p_set_snapshot_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      let $ = $two_p_set.from_json(encoded);
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new TwoPSetSnapshot(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "TwoPSetSnapshot",
        );
      }
    },
  );
}

function g_set_snapshot_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      let $ = $g_set.from_json(encoded);
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new GSetSnapshot(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "GSetSnapshot",
        );
      }
    },
  );
}

function or_set_snapshot_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      let $ = $or_set.from_json(encoded);
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new OrSetSnapshot(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "ORSetSnapshot",
        );
      }
    },
  );
}

function or_map_snapshot_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      return $decode.then$(
        (() => {
          let $ = $json.parse(
            encoded,
            $decode.at(toList(["state", "replica_id"]), $decode.string),
          );
          if ($ instanceof Ok) {
            let author = $[0];
            return $decode.success(author);
          } else {
            return $decode.failure("", "ORMapSnapshot");
          }
        })(),
        (author) => {
          let $ = $or_map_kernel.from_summary(encoded, $replica_id.new$(author));
          if ($ instanceof Ok) {
            let kernel = $[0];
            return $decode.success(
              new OrMapSnapshot(kernel.mode, kernel.sequenced),
            );
          } else {
            return $decode.failure(
              new MapSnapshot($List$Empty$const),
              "ORMapSnapshot",
            );
          }
        },
      );
    },
  );
}

/**
 * Decode the current register envelope without Lattice's legacy author
 * default. Only the empty bottom state may have an empty author.
 */
export function lww_register_decoder() {
  return $decode.field(
    "type",
    $decode.string,
    (tag) => {
      return $decode.field(
        "v",
        $decode.int,
        (version) => {
          return $decode.then$(
            $decode.at(toList(["state", "value"]), $decode.string),
            (value) => {
              return $decode.then$(
                $decode.at(toList(["state", "timestamp"]), $decode.int),
                (timestamp) => {
                  return $decode.then$(
                    $decode.at(toList(["state", "replica_id"]), $decode.string),
                    (author) => {
                      let valid = ((((tag === "lww_register") && (version === 2)) && (timestamp >= 0)) && (timestamp <= $lww_clock.max_safe_timestamp)) && ((author !== "") || ((value === "") && (timestamp === 0)));
                      if (valid) {
                        return $decode.success(
                          $lww_register.new$(
                            value,
                            timestamp,
                            $replica_id.new$(author),
                          ),
                        );
                      } else {
                        return $decode.failure(
                          $lww_register.new$("", 0, $replica_id.new$("")),
                          "version 2 LWW register with a safe timestamp and winner author",
                        );
                      }
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

function mv_register_snapshot_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let $ = $mv_register_kernel.decode_crdt($json.to_string(value));
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new MvRegisterSnapshot(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "MvRegisterSnapshot",
        );
      }
    },
  );
}

function g_counter_snapshot_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      let $ = $g_counter.from_json(encoded);
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new GCounterSnapshot(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "GCounterSnapshot",
        );
      }
    },
  );
}

function pn_counter_snapshot_decoder() {
  return $decode.then$(
    $wire.json_value_decoder(),
    (value) => {
      let encoded = $json.to_string(value);
      let $ = $pn_counter.from_json(encoded);
      if ($ instanceof Ok) {
        let state = $[0];
        return $decode.success(new PnCounterSnapshot(state));
      } else {
        return $decode.failure(
          new MapSnapshot($List$Empty$const),
          "PnCounterSnapshot",
        );
      }
    },
  );
}

/**
 * The decoder for a snapshot payload. The channel type selects it, and the
 * envelope that carries the payload names that type in a field.
 */
export function snapshot_decoder(channel_type) {
  if (channel_type instanceof MapChannel) {
    let _pipe = $decode.list($wire.entry_decoder());
    return $decode.map(_pipe, (var0) => { return new MapSnapshot(var0); });
  } else if (channel_type instanceof CounterChannel) {
    let _pipe = $decode.int;
    return $decode.map(_pipe, (var0) => { return new CounterSnapshot(var0); });
  } else if (channel_type instanceof PnCounterChannel) {
    return pn_counter_snapshot_decoder();
  } else if (channel_type instanceof GCounterChannel) {
    return g_counter_snapshot_decoder();
  } else if (channel_type instanceof LwwRegisterChannel) {
    let _pipe = lww_register_decoder();
    return $decode.map(
      _pipe,
      (var0) => { return new LwwRegisterSnapshot(var0); },
    );
  } else if (channel_type instanceof LwwMapChannel) {
    let _pipe = $lww_map_kernel.decoder();
    return $decode.map(_pipe, (var0) => { return new LwwMapSnapshot(var0); });
  } else if (channel_type instanceof MvRegisterChannel) {
    return mv_register_snapshot_decoder();
  } else if (channel_type instanceof OrMapChannel) {
    return or_map_snapshot_decoder();
  } else if (channel_type instanceof OrSetChannel) {
    return or_set_snapshot_decoder();
  } else if (channel_type instanceof GSetChannel) {
    return g_set_snapshot_decoder();
  } else if (channel_type instanceof TwoPSetChannel) {
    return two_p_set_snapshot_decoder();
  } else if (channel_type instanceof RegisterCollectionChannel) {
    let _pipe = $decode.list(register_entry_decoder());
    return $decode.map(
      _pipe,
      (var0) => { return new RegisterCollectionSnapshot(var0); },
    );
  } else if (channel_type instanceof ClaimsChannel) {
    let _pipe = $decode.list(claim_entry_decoder());
    return $decode.map(_pipe, (var0) => { return new ClaimsSnapshot(var0); });
  } else if (channel_type instanceof TaskManagerChannel) {
    let _pipe = $decode.list(task_queue_decoder());
    return $decode.map(
      _pipe,
      (var0) => { return new TaskManagerSnapshot(var0); },
    );
  } else if (channel_type instanceof PactMapChannel) {
    let _pipe = $decode.list(pact_entry_decoder());
    return $decode.map(_pipe, (var0) => { return new PactMapSnapshot(var0); });
  } else if (channel_type instanceof JsonOtChannel) {
    let _pipe = $json_ot.decoder();
    return $decode.map(_pipe, (var0) => { return new JsonOtSnapshot(var0); });
  } else if (channel_type instanceof DirectoryChannel) {
    let _pipe = directory_summary_decoder();
    return $decode.map(_pipe, (var0) => { return new DirectorySnapshot(var0); });
  } else if (channel_type instanceof OrderedCollectionChannel) {
    return ordered_snapshot_decoder();
  } else if (channel_type instanceof SequenceChannel) {
    return sequence_summary_decoder();
  } else if (channel_type instanceof RichTextChannel) {
    return rich_text_snapshot_decoder();
  } else {
    return text_summary_decoder();
  }
}
