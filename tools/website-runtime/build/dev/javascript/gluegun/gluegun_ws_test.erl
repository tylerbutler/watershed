-module(gluegun_ws_test).

-export([
    capture_ws_send_frame_message/1,
    capture_ws_send_message/0,
    capture_ws_upgrade_options/1,
    current_process/0,
    invalid_ws_send_frame_result/0,
    invalid_ws_send_frame_list_result/0,
    invalid_ws_send_text_utf8_result/0,
    invalid_ws_upgrade_unknown_option_result/0,
    invalid_ws_upgrade_options_result/0,
    test_close_plain_message/0,
    test_close_with_reason_message/0,
    test_ws_close_gun_tuple/0,
    test_ws_close_with_reason_gun_tuple/0
]).

capture_ws_send_frame_message(Frame) ->
    StreamRef = make_ref(),
    case gluegun_ffi:ws_send(self(), StreamRef, Frame) of
        {ok, nil} ->
            receive
                {'$gen_cast', {ws_send, _ReplyTo, StreamRef, GunFrame}} ->
                    {ok, #{<<"type">> => <<"websocket">>,
                           <<"frame">> => gun_frame_to_map(GunFrame)}}
            after 0 ->
                {error, no_ws_send_message}
            end;
        Error ->
            Error
    end.


capture_ws_send_message() ->
    receive
        {'$gen_cast', {ws_send, _ReplyTo, _StreamRef, GunFrames}} when is_list(GunFrames) ->
            {ok, [gun_frame_to_pair(Frame) || Frame <- GunFrames]};
        {'$gen_cast', {ws_send, _ReplyTo, _StreamRef, GunFrame}} ->
            {ok, [gun_frame_to_pair(GunFrame)]}
    after 0 ->
        {error, nil}
    end.

capture_ws_upgrade_options(Options) ->
    case gluegun_ffi:ws_upgrade(self(), <<"/ws">>, [], Options) of
        {ok, StreamRef} ->
            receive
                {'$gen_cast', {ws_upgrade, _ReplyTo, StreamRef, _Path, _Headers, GunOpts}} ->
                    {ok, ws_opts_to_assertion_map(GunOpts)}
            after 0 ->
                {error, no_ws_upgrade_message}
            end;
        Error ->
            Error
    end.


invalid_ws_send_frame_result() ->
    gluegun_ffi:ws_send(self(), make_ref(), bad_frame).

invalid_ws_send_frame_list_result() ->
    gluegun_ffi:ws_send(self(), make_ref(), [{text, <<"ok">>}, bad_frame]).

invalid_ws_send_text_utf8_result() ->
    gluegun_ffi:ws_send(self(), make_ref(), {text, <<255>>}).

invalid_ws_upgrade_options_result() ->
    gluegun_ffi:ws_upgrade(self(), <<"/ws">>, [], #{<<"compress">> => <<"not-a-boolean">>}).

invalid_ws_upgrade_unknown_option_result() ->
    gluegun_ffi:ws_upgrade(self(), <<"/ws">>, [], #{<<"unexpected_ws_option">> => true}).

current_process() ->
    self().

%% Pre-built message maps matching the new FFI output for plain close.
%% frame type "close" has no code/reason fields.
test_close_plain_message() ->
    #{<<"type">> => <<"websocket">>,
      <<"frame">> => #{<<"type">> => <<"close">>}}.

%% Pre-built message map for close with reason.
%% frame type "close_with_reason" carries code and reason as bit_array.
test_close_with_reason_message() ->
    #{<<"type">> => <<"websocket">>,
      <<"frame">> => #{<<"type">> => <<"close_with_reason">>,
                       <<"code">> => 1001,
                       <<"reason">> => <<"going away">>}}.

%% Raw Gun message tuples, used with gluegun_ffi:safe_message_to_map/1
%% to test that the FFI conversion produces the expected map shapes.
test_ws_close_gun_tuple() ->
    {ws, close}.

test_ws_close_with_reason_gun_tuple() ->
    {ws, {close, 1001, <<"going away">>}}.

gun_frame_to_pair({text, Data}) -> {<<"text">>, Data};
gun_frame_to_pair({binary, Data}) -> {<<"binary">>, Data};
gun_frame_to_pair({ping, Data}) -> {<<"ping">>, Data};
gun_frame_to_pair({pong, Data}) -> {<<"pong">>, Data};
gun_frame_to_pair(close) -> {<<"close">>, <<>>};
gun_frame_to_pair({close, Code, Reason}) -> {<<"close_with_reason">>, <<(integer_to_binary(Code))/binary, $:, Reason/binary>>}.

gun_frame_to_map({text, Data}) ->
    #{<<"type">> => <<"text">>, <<"data">> => Data};
gun_frame_to_map({binary, Data}) ->
    #{<<"type">> => <<"binary">>, <<"data">> => Data};
gun_frame_to_map({ping, Data}) ->
    #{<<"type">> => <<"ping">>, <<"data">> => Data};
gun_frame_to_map({pong, Data}) ->
    #{<<"type">> => <<"pong">>, <<"data">> => Data};
gun_frame_to_map(close) ->
    #{<<"type">> => <<"close">>};
gun_frame_to_map({close, Code, Reason}) ->
    #{<<"type">> => <<"close_with_reason">>,
      <<"code">> => Code,
      <<"reason">> => Reason}.


ws_opts_to_assertion_map(GunOpts) when is_map(GunOpts) ->
    maps:from_list([{atom_to_binary(Key, utf8), ws_opt_value_to_assertion(Value)} || {Key, Value} <- maps:to_list(GunOpts)]).

ws_opt_value_to_assertion(Protocols) when is_list(Protocols) ->
    [ws_protocol_to_assertion(Protocol) || Protocol <- Protocols];
ws_opt_value_to_assertion(Value) ->
    Value.

ws_protocol_to_assertion({Protocol, Module}) ->
    {Protocol, Module};
ws_protocol_to_assertion([Protocol, Module]) ->
    {Protocol, Module}.
