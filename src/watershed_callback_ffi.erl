-module(watershed_callback_ffi).
-export([capture/3]).

capture(Work, OnSuccess, OnError) ->
    try Work() of
        Value -> OnSuccess(Value)
    catch
        Class:Reason ->
            OnError(iolist_to_binary(io_lib:format("~tp: ~tp", [Class, Reason])))
    end.
