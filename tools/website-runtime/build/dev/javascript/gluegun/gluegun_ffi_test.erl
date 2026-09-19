-module(gluegun_ffi_test).

-export([
    test_response_message/0,
    test_data_message/0,
    test_stream_ref/0,
    test_erlang_error/0,
    test_stream_error/0,
    test_invalid_utf8_websocket/0
]).

test_response_message() ->
    #{<<"type">> => <<"response">>, <<"fin">> => true, <<"status">> => 200, <<"headers">> => [{<<"Content-Type">>, <<"text/plain">>}]}.

test_data_message() ->
    #{<<"type">> => <<"data">>, <<"fin">> => false, <<"data">> => <<"hello">>}.

test_stream_ref() ->
    make_ref().

test_erlang_error() ->
    {erlang_error, {error, badarg}}.

test_stream_error() ->
    {stream_error, boom}.

test_invalid_utf8_websocket() ->
    {ws, {text, <<255>>}}.
