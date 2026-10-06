-module(settlement_trace).
-export([start/2, seal/2, await_idle/2, stop/2]).

start({subject, Runtime, _Selector}, Timeout) ->
    Caller = self(),
    ReadyRef = make_ref(),
    Tracer = spawn(fun() -> init(Runtime, Caller, ReadyRef) end),
    Monitor = erlang:monitor(process, Tracer),
    receive
        {ReadyRef, Tracer, ready} ->
            erlang:demonitor(Monitor, [flush]),
            {ok, Tracer};
        {ReadyRef, Tracer, {error, Message}} ->
            await_down(Monitor, Tracer, Timeout),
            {error, Message};
        {'DOWN', Monitor, process, Tracer, _Reason} ->
            {error, <<"settlement trace exited during startup">>}
    after Timeout ->
        exit(Tracer, shutdown),
        await_down(Monitor, Tracer, Timeout),
        {error, <<"settlement trace startup timed out">>}
    end.

seal(Tracer, Timeout) ->
    request(Tracer, seal, Timeout).

await_idle(Tracer, Timeout) ->
    request(Tracer, await_idle, Timeout).

stop(Tracer, Timeout) ->
    Monitor = erlang:monitor(process, Tracer),
    RequestRef = make_ref(),
    Tracer ! {stop, self(), RequestRef},
    receive
        {'DOWN', Monitor, process, Tracer, normal} ->
            {ok, nil};
        {'DOWN', Monitor, process, Tracer, _Reason} ->
            {error, <<"settlement trace cleanup failed">>}
    after Timeout ->
        exit(Tracer, shutdown),
        await_down(Monitor, Tracer, Timeout),
        {error, <<"settlement trace cleanup timed out">>}
    end.

request(Tracer, Operation, Timeout) ->
    Monitor = erlang:monitor(process, Tracer),
    RequestRef = make_ref(),
    Tracer ! {Operation, self(), RequestRef},
    receive
        {RequestRef, complete} ->
            erlang:demonitor(Monitor, [flush]),
            {ok, nil};
        {'DOWN', Monitor, process, Tracer, _Reason} ->
            {error, <<"settlement trace exited before completing request">>}
    after Timeout ->
        erlang:demonitor(Monitor, [flush]),
        {error, <<"settlement trace request timed out">>}
    end.

await_down(Monitor, Process, Timeout) ->
    receive
        {'DOWN', Monitor, process, Process, _Reason} -> ok
    after Timeout ->
        erlang:demonitor(Monitor, [flush]),
        timeout
    end.

init(Runtime, Caller, ReadyRef) ->
    try erlang:trace(Runtime, true, [procs, set_on_spawn, {tracer, self()}]) of
        1 ->
            Caller ! {ReadyRef, self(), ready},
            collecting(Runtime, #{});
        _ ->
            Caller ! {
                ReadyRef,
                self(),
                {error, <<"settlement trace runtime is not alive">>}
            }
    catch
        error:badarg ->
            Caller ! {
                ReadyRef,
                self(),
                {error, <<"settlement trace runtime is not alive">>}
            }
    end.

collecting(Runtime, Live) ->
    receive
        {trace, Runtime, spawn, Child, _Mfa} ->
            Monitor = erlang:monitor(process, Child),
            collecting(Runtime, maps:put(Monitor, Child, Live));
        {trace, _Process, spawn, _Child, _Mfa} ->
            collecting(Runtime, Live);
        {'DOWN', Monitor, process, _Process, _Reason} ->
            collecting(Runtime, maps:remove(Monitor, Live));
        {seal, From, RequestRef} ->
            DeliveryRef = erlang:trace_delivered(Runtime),
            sealing(Runtime, Live, From, RequestRef, DeliveryRef);
        {stop, _From, _RequestRef} ->
            finish(Runtime, Live)
    end.

sealing(Runtime, Live, From, RequestRef, DeliveryRef) ->
    receive
        {trace, Runtime, spawn, Child, _Mfa} ->
            Monitor = erlang:monitor(process, Child),
            sealing(
                Runtime,
                maps:put(Monitor, Child, Live),
                From,
                RequestRef,
                DeliveryRef
            );
        {trace, _Process, spawn, _Child, _Mfa} ->
            sealing(Runtime, Live, From, RequestRef, DeliveryRef);
        {'DOWN', Monitor, process, _Process, _Reason} ->
            sealing(
                Runtime,
                maps:remove(Monitor, Live),
                From,
                RequestRef,
                DeliveryRef
            );
        {trace_delivered, Runtime, DeliveryRef} ->
            _ = erlang:trace(Runtime, false, [all]),
            From ! {RequestRef, complete},
            sealed(Runtime, Live, none);
        {stop, _StopFrom, _StopRef} ->
            finish(Runtime, Live)
    end.

sealed(Runtime, Live, Waiter) ->
    receive
        {'DOWN', Monitor, process, _Process, _Reason} ->
            Next = maps:remove(Monitor, Live),
            case {maps:size(Next), Waiter} of
                {0, {From, RequestRef}} ->
                    From ! {RequestRef, complete},
                    sealed(Runtime, Next, none);
                _ ->
                    sealed(Runtime, Next, Waiter)
            end;
        {await_idle, From, RequestRef} when map_size(Live) =:= 0 ->
            From ! {RequestRef, complete},
            sealed(Runtime, Live, Waiter);
        {await_idle, From, RequestRef} ->
            sealed(Runtime, Live, {From, RequestRef});
        {stop, _From, _RequestRef} ->
            finish(Runtime, Live)
    end.

finish(Runtime, Live) ->
    _ =
        try erlang:trace(Runtime, false, [all])
        catch
            error:badarg -> false
        end,
    maps:foreach(
        fun(Monitor, _Process) -> erlang:demonitor(Monitor, [flush]) end,
        Live
    ),
    ok.
