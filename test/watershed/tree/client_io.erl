-module(client_io).
-export([descriptor/0, token/0, read_line/0, write_line/1, fail/1]).

descriptor() ->
    {ok, Bytes} = file:read_file(required("WATERSHED_DESCRIPTOR")),
    Bytes.

token() -> unicode:characters_to_binary(required("WATERSHED_TOKEN")).

required(Name) ->
    case os:getenv(Name) of
        false -> erlang:error({missing_environment, Name});
        Value -> Value
    end.

read_line() ->
    case io:get_line("") of
        eof -> {error, nil};
        {error, Reason} -> erlang:error({stdin_error, Reason});
        Line -> {ok, unicode:characters_to_binary(Line)}
    end.

write_line(Value) ->
    ok = io:put_chars([Value, "\n"]),
    nil.

fail(Value) ->
    io:format(standard_error, "~ts~n", [Value]),
    erlang:halt(1).
