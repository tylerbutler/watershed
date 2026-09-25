-module(client_io).
-export([descriptor/0, token/0, read_line/0, write_line/1, fail/1]).

descriptor() ->
    case os:getenv("WATERSHED_DESCRIPTOR") of
        false ->
            startup("descriptor-decode-failed", "descriptor",
                "Missing WATERSHED_DESCRIPTOR");
        Path ->
            case file:read_file(Path) of
                {ok, Bytes} -> Bytes;
                {error, Reason} ->
                    startup("descriptor-decode-failed", "descriptor",
                        ["Could not read descriptor: ", atom_to_list(Reason)])
            end
    end.

token() ->
    case os:getenv("WATERSHED_TOKEN") of
        false -> startup("bootstrap-failed", "connect", "Missing WATERSHED_TOKEN");
        Value -> unicode:characters_to_binary(Value)
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

startup(Code, Operation, Message) ->
    Encoded = io_lib:format(
        "{\"kind\":\"startup-error\",\"code\":\"~ts\",\"operation\":\"~ts\",\"message\":\"~ts\"}",
        [escape(Code), escape(Operation), escape(Message)]
    ),
    fail(Encoded).

escape(Value) ->
    Bytes = unicode:characters_to_binary(Value),
    EscapedSlash = binary:replace(Bytes, <<"\\">>, <<"\\\\">>, [global]),
    EscapedQuote = binary:replace(EscapedSlash, <<"\"">>, <<"\\\"">>, [global]),
    EscapedReturn = binary:replace(EscapedQuote, <<"\r">>, <<"\\r">>, [global]),
    binary:replace(EscapedReturn, <<"\n">>, <<"\\n">>, [global]).
