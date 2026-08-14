import gleam/list
import startest/expect

import watershed/channel
import watershed/or_map_kernel
import watershed/p2p

fn channel_cases() -> List(#(channel.ChannelType, Bool)) {
  [
    #(channel.MapChannel, False),
    #(channel.CounterChannel, False),
    #(channel.PnCounterChannel, True),
    #(channel.OrMapChannel, True),
    #(channel.OrSetChannel, True),
    #(channel.GSetChannel, True),
    #(channel.TwoPSetChannel, True),
    #(channel.RegisterCollectionChannel, False),
    #(channel.ClaimsChannel, False),
    #(channel.TaskManagerChannel, False),
    #(channel.PactMapChannel, False),
    #(channel.JsonOtChannel, False),
    #(channel.DirectoryChannel, False),
    #(channel.OrderedCollectionChannel, False),
    #(channel.SequenceChannel, True),
    #(channel.RichTextChannel, False),
    #(channel.TextChannel, True),
  ]
}

fn unsupported_types() -> List(channel.ChannelType) {
  channel_cases()
  |> list.filter_map(fn(entry) {
    let #(channel_type, supported) = entry
    case supported {
      True -> Error(Nil)
      False -> Ok(channel_type)
    }
  })
}

fn supported_inits() -> List(channel.ChannelInit) {
  [
    channel.InitPnCounter,
    channel.InitOrMap(or_map_kernel.RegisterMode),
    channel.InitOrSet,
    channel.InitGSet,
    channel.InitTwoPSet,
    channel.InitSequence,
    channel.InitText,
  ]
}

pub fn every_channel_has_an_explicit_p2p_eligibility_test() {
  channel_cases()
  |> list.each(fn(entry) {
    let #(channel_type, supported) = entry
    channel.supports_p2p(channel_type) |> expect.to_equal(supported)
  })
}

pub fn typed_root_constructors_cover_every_eligible_kind_test() {
  [
    p2p.pn_counter_root() |> p2p.kind_type,
    p2p.or_map_root(or_map_kernel.RegisterMode) |> p2p.kind_type,
    p2p.or_set_root() |> p2p.kind_type,
    p2p.g_set_root() |> p2p.kind_type,
    p2p.two_p_set_root() |> p2p.kind_type,
    p2p.sequence_root() |> p2p.kind_type,
    p2p.text_root() |> p2p.kind_type,
  ]
  |> expect.to_equal([
    channel.PnCounterChannel,
    channel.OrMapChannel,
    channel.OrSetChannel,
    channel.GSetChannel,
    channel.TwoPSetChannel,
    channel.SequenceChannel,
    channel.TextChannel,
  ])
}

pub fn unsupported_channel_types_are_rejected_test() {
  unsupported_types()
  |> list.each(fn(channel_type) {
    p2p.validate(channel_type)
    |> expect.to_equal(Error(p2p.UnsupportedChannel(channel_type)))
  })
}

pub fn unsupported_create_paths_are_rejected_test() {
  [
    channel.InitMap,
    channel.InitCounter,
    channel.InitRegisterCollection,
    channel.InitClaims,
    channel.InitTaskManager,
    channel.InitPactMap,
    channel.InitJsonOt,
    channel.InitDirectory,
    channel.InitOrderedCollection,
    channel.InitRichText,
  ]
  |> list.each(fn(init) {
    p2p.validate_create(init)
    |> expect.to_equal(Error(p2p.UnsupportedChannel(channel.init_type(init))))
  })
}

pub fn eligible_boundary_paths_are_accepted_test() {
  supported_inits()
  |> list.each(fn(init) {
    let channel_type = channel.init_type(init)
    p2p.validate(channel_type) |> expect.to_equal(Ok(channel_type))
    p2p.validate_create(init) |> expect.to_equal(Ok(init))
  })
}
