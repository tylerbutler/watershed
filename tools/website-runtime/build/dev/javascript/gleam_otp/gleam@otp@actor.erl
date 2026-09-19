-module(gleam@otp@actor).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([continue/1, stop/0, stop_abnormal/1, with_selector/2, initialised/1, selecting/2, returning/2, new/1, new_with_initialiser/2, on_message/2, named/2, start/1, send/2, call/3]).
-export_type([message/1, next/2, self/2, started/1, initialised/3, builder/3, start_error/0, start_init_message/1]).
-moduledoc(~" This module provides the _Actor_ abstraction, one of the most common
 building blocks of Gleam OTP programs.

 An Actor is a process like any other BEAM process and can be used to hold
 state, execute code, and communicate with other processes by sending and
 receiving messages. The advantage of using the actor abstraction over a bare
 process is that it provides a single interface for commonly needed
 functionality, including support for the [tracing and debugging
 features in OTP][erlang-sys].

 Gleam's Actor is similar to Erlang's `gen_server` and Elixir's `GenServer`
 but differs in that it offers a fully typed interface. This different API is
 why Gleam uses the name \"Actor\" rather than some variation of
 \"generic-server\".

 [erlang-sys]: https://www.erlang.org/doc/man/sys.html

 ## Example

 An Actor can be used to create a client-server interaction between an Actor
 (the server) and other processes (the clients). In this example we have an
 Actor that works as a stack, allowing clients to push and pop elements.

 ```gleam
 pub fn main() {
   // Start the actor with initial state of an empty list, and the
   // `handle_message` callback function (defined below).
   // We assert that it starts successfully.
   // 
   // In real-world Gleam OTP programs we would likely write a wrapper functions
   // called `start`, `push` `pop`, `shutdown` to start and interact with the
   // Actor. We are not doing that here for the sake of showing how the Actor 
   // API works.
   let assert Ok(actor) =
     actor.new([]) |> actor.on_message(handle_message) |> actor.start
   let subject = actor.data

   // We can send a message to the actor to push elements onto the stack.
   process.send(subject, Push(\"Joe\"))
   process.send(subject, Push(\"Mike\"))
   process.send(subject, Push(\"Robert\"))

   // The `Push` message expects no response, these messages are sent purely for
   // the side effect of mutating the state held by the actor.
   //
   // We can also send the `Pop` message to take a value off of the actor's
   // stack. This message expects a response, so we use `process.call` to send a
   // message and wait until a reply is received.
   //
   // In this instance we are giving the actor 10 milliseconds to reply, if the
   // `call` function doesn't get a reply within this time it will panic and
   // crash the client process.
   let assert Ok(\"Robert\") = process.call(subject, 10, Pop)
   let assert Ok(\"Mike\") = process.call(subject, 10, Pop)
   let assert Ok(\"Joe\") = process.call(subject, 10, Pop)

   // The stack is now empty, so if we pop again the actor replies with an error.
   let assert Error(Nil) = process.call(subject, 10, Pop)

   // Lastly, we can send a message to the actor asking it to shut down.
   process.send(subject, Shutdown)
 }
 ```

 Here is the code that is used to implement this actor:

 ```gleam
 // First step of implementing the stack Actor is to define the message type that
 // it can receive.
 //
 // The type of the elements in the stack is not fixed so a type parameter
 // is used for it instead of a concrete type such as `String` or `Int`.
 pub type Message(element) {
   // The `Shutdown` message is used to tell the actor to stop.
   // It is the simplest message type, it contains no data.
   //
   // Most the time we don't define an API to shut down an actor, but in this
   // example we do to show how it can be done.
   Shutdown
 
   // The `Push` message is used to add a new element to the stack.
   // It contains the item to add, the type of which is the `element`
   // parameterised type.
   Push(push: element)
 
   // The `Pop` message is used to remove an element from the stack.
   // It contains a `Subject`, which is used to send the response back to the
   // message sender. In this case the reply is of type `Result(element, Nil)`.
   Pop(reply_with: Subject(Result(element, Nil)))
 }
 
 // The last part is to implement the `handle_message` callback function.
 //
 // This function is called by the Actor for each message it receives.
 // Actors are single threaded only doing one thing at a time, so they handle
 // messages sequentially one at a time, in the order they are received.
 //
 // The function takes the current state and a message, and returns a data
 // structure that indicates what to do next, along with the new state.
 fn handle_message(
   stack: List(e),
   message: Message(e),
 ) -> actor.Next(List(e), Message(e)) {
   case message {
     // For the `Shutdown` message we return the `actor.stop` value, which causes
     // the actor to discard any remaining messages and stop.
     // We may choose to do some clean-up work here, but this actor doesn't need
     // to do this.
     Shutdown -> actor.stop()
 
     // For the `Push` message we add the new element to the stack and return
     // `actor.continue` with this new stack, causing the actor to process any
     // queued messages or wait for more.
     Push(value) -> {
       let new_state = [value, ..stack]
       actor.continue(new_state)
     }
 
     // For the `Pop` message we attempt to remove an element from the stack,
     // sending it or an error back to the caller, before continuing.
     Pop(client) -> {
       case stack {
         [] -> {
           // When the stack is empty we can't pop an element, so we send an
           // error back.
           process.send(client, Error(Nil))
           actor.continue([])
         }
 
         [first, ..rest] -> {
           // Otherwise we send the first element back and use the remaining
           // elements as the new state.
           process.send(client, Ok(first))
           actor.continue(rest)
         }
       }
     }
   }
 }
 ```").

-type message(DUU) :: {message, DUU} | {system, gleam@otp@system:system_message()} | {unexpected, gleam@dynamic:dynamic_()}.

-opaque next(DUV, DUW) :: {continue, DUV, gleam@option:option(gleam@erlang@process:selector(DUW))} | {stop, gleam@erlang@process:exit_reason()}.

-type self(DUX, DUY) :: {self, gleam@otp@system:mode(), gleam@erlang@process:pid_(), DUX, gleam@erlang@process:selector(message(DUY)), gleam@otp@system:debug_state(), fun((DUX, DUY) -> next(DUX, DUY))}.

-type started(DUZ) :: {started, gleam@erlang@process:pid_(), DUZ}.

-opaque initialised(DVA, DVB, DVC) :: {initialised, DVA, gleam@option:option(gleam@erlang@process:selector(DVB)), DVC}.

-opaque builder(DVD, DVE, DVF) :: {builder, fun((gleam@erlang@process:subject(DVE)) -> {ok, initialised(DVD, DVE, DVF)} | {error, binary()}), integer(), fun((DVD, DVE) -> next(DVD, DVE)), gleam@option:option(gleam@erlang@process:name(DVE))}.

-type start_error() :: init_timeout | {init_failed, binary()} | {init_exited, gleam@erlang@process:exit_reason()}.

-type start_init_message(DVG) :: {ack, {ok, DVG} | {error, binary()}} | {mon, gleam@erlang@process:down()}.

-file("src/gleam/otp/actor.gleam", 185).
-spec continue(DVL) -> next(DVL, any()).
-doc(~" Indicate the actor should continue, processing any waiting or future messages.
").
continue(State) ->
    {continue, State, none}.

-file("src/gleam/otp/actor.gleam", 193).
-spec stop() -> next(any(), any()).
-doc(~" Indicate the actor should stop and shut-down, handling no futher messages.

 The reason for exiting is `Normal`.
").
stop() ->
    {stop, normal}.

-file("src/gleam/otp/actor.gleam", 202).
-spec stop_abnormal(binary()) -> next(any(), any()).
-doc(~" Indicate the actor is in a bad state and should shut down. It will not
 handle any new messages, and any linked processes will also exit abnormally.

 The provided reason will be given and propagated.
").
stop_abnormal(Reason) ->
    {stop, {abnormal, gleam_stdlib:identity(Reason)}}.

-file("src/gleam/otp/actor.gleam", 210).
-spec with_selector(next(DVX, DVY), gleam@erlang@process:selector(DVY)) -> next(DVX, DVY).
-doc(~" Provide a selector to change the messages that the actor is handling
 going forward. This replaces any selector that was previously given
 in the actor's `init` callback, or in any previous `Next` value.
").
with_selector(Value, Selector) ->
    case Value of
        {continue, State, _} ->
            {continue, State, {some, Selector}};

        {stop, _} ->
            Value
    end.

-file("src/gleam/otp/actor.gleam", 268).
-spec initialised(DWE) -> initialised(DWE, any(), nil).
-doc(~" Takes the post-initialisation state of the actor. This state will be passed
 to the `on_message` callback each time a message is received.
").
initialised(State) ->
    {initialised, State, none, nil}.

-file("src/gleam/otp/actor.gleam", 277).
-spec selecting(initialised(DWJ, any(), DWL), gleam@erlang@process:selector(DWP)) -> initialised(DWJ, DWP, DWL).
-doc(~" Add a selector for the actor to receive messages with.

 If a message is received by the actor but not selected for with the
 selector then the actor will discard it and log a warning.
").
selecting(Initialised, Selector) ->
    {initialised, erlang:element(2, Initialised), {some, Selector}, erlang:element(4, Initialised)}.

-file("src/gleam/otp/actor.gleam", 287).
-spec returning(initialised(DWU, DWV, any()), DXA) -> initialised(DWU, DWV, DXA).
-doc(~" Add the data to return to the parent process. This might be a subject that
 the actor will receive messages over.
").
returning(Initialised, Return) ->
    {initialised, erlang:element(2, Initialised), erlang:element(3, Initialised), Return}.

-file("src/gleam/otp/actor.gleam", 329).
-spec new(DXE) -> builder(DXE, DXF, gleam@erlang@process:subject(DXF)).
-doc(~" Create a builder for an actor without a custom initialiser. The actor
 returns a subject to the parent that can be used to send messages to the
 actor.

 If the actor has been given a name with the `named` function then the
 subject is a named subject.

 If you wish to create an actor with some other initialisation logic that
 runs before it starts handling messages, see `new_with_initialiser`.
").
new(State) ->
    Initialise = fun(Subject) ->
        _pipe = initialised(State),
        _pipe@1 = returning(_pipe, Subject),
        {ok, _pipe@1}
    end,
    {builder, Initialise, 1000, fun(State@1, _) ->
        continue(State@1)
    end, none}.

-file("src/gleam/otp/actor.gleam", 358).
-spec new_with_initialiser(integer(), fun((gleam@erlang@process:subject(DXK)) -> {ok, initialised(DXM, DXK, DXN)} | {error, binary()})) -> builder(DXM, DXK, DXN).
-doc(~" Create a builder for an actor with a custom initialiser that runs before
 the start function returns to the parent, and before the actor starts
 handling messages.

 The first argument is a number of milliseconds that the initialiser
 function is expected to return within. If it takes longer the initialiser
 is considered to have failed and the actor will be killed, and an error
 will be returned to the parent.

 The actor's default subject is passed to the initialiser function. You can
 choose to return it to the parent with `returning`, use it in some other
 way, or ignore it completely.

 If a custom selector is given using the `selecting` function then this
 overwrites the default selector, which selects for the default subject, so
 you will need to add the subject to the custom selector yourself.
").
new_with_initialiser(Timeout, Initialise) ->
    {builder, Initialise, Timeout, fun(State, _) ->
        continue(State)
    end, none}.

-file("src/gleam/otp/actor.gleam", 376).
-spec on_message(builder(DXW, DXX, DXY), fun((DXW, DXX) -> next(DXW, DXX))) -> builder(DXW, DXX, DXY).
-doc(~" Set the message handler for the actor. This callback function will be
 called each time the actor receives a message.

 Actors handle messages sequentially, later messages being handled after the
 previous one has been handled.").
on_message(Builder, Handler) ->
    {builder, erlang:element(2, Builder), erlang:element(3, Builder), Handler, erlang:element(5, Builder)}.

-file("src/gleam/otp/actor.gleam", 395).
-spec named(builder(DYH, DYI, DYJ), gleam@erlang@process:name(DYI)) -> builder(DYH, DYI, DYJ).
-doc(~" Provide a name for the actor to be registered with when started, enabling
 it to receive messages via a named subject. This is useful for making
 processes that can take over from an older one that has exited due to a
 failure, or to avoid passing subjects from receiver processes to sender
 processes.

 If the name is already registered to another process then the actor will
 fail to start.

 When this function is used the actor's default subject will be a named
 subject using this name.
").
named(Builder, Name) ->
    {builder, erlang:element(2, Builder), erlang:element(3, Builder), erlang:element(4, Builder), {some, Name}}.

-file("src/gleam/otp/actor.gleam", 402).
-spec exit_process(gleam@erlang@process:exit_reason()) -> gleam@erlang@process:exit_reason().
exit_process(Reason) ->
    case Reason of
        {abnormal, Reason@1} ->
            gleam@erlang@process:send_abnormal_exit(erlang:self(), Reason@1);

        killed ->
            gleam@erlang@process:kill(erlang:self());

        _ ->
            nil
    end,
    Reason.

-file("src/gleam/otp/actor.gleam", 443).
-spec select_system_messages(gleam@erlang@process:selector(message(DYW))) -> gleam@erlang@process:selector(message(DYW)).
select_system_messages(Selector) ->
    _pipe = Selector,
    gleam@erlang@process:select_record(_pipe, erlang:binary_to_atom(~"system"), 2, fun gleam_otp_external:convert_system_message/1).

-file("src/gleam/otp/actor.gleam", 412).
-spec receive_message(self(any(), DYS)) -> message(DYS).
receive_message(Self) ->
    Selector = case erlang:element(2, Self) of
        suspended ->
            _pipe = gleam_erlang_ffi:new_selector(),
            select_system_messages(_pipe);

        running ->
            _pipe@1 = gleam_erlang_ffi:new_selector(),
            _pipe@2 = gleam@erlang@process:select_other(_pipe@1, fun(_value) ->
                {unexpected, _value}
            end),
            _pipe@3 = gleam_erlang_ffi:merge_selector(_pipe@2, erlang:element(5, Self)),
            select_system_messages(_pipe@3)
    end,
    gleam_erlang_ffi:select(Selector).

-file("src/gleam/otp/actor.gleam", 453).
-spec process_status_info(self(any(), any())) -> gleam@otp@system:status_info().
process_status_info(Self) ->
    {status_info, erlang:binary_to_atom(~"gleam@otp@actor"), erlang:element(3, Self), erlang:element(2, Self), erlang:element(6, Self), gleam_otp_external:identity(erlang:element(4, Self))}.

-file("src/gleam/otp/actor.gleam", 463).
-spec loop(self(any(), any())) -> gleam@erlang@process:exit_reason().
loop(Self) ->
    case receive_message(Self) of
        {system, System} ->
            case System of
                {get_state, Callback} ->
                    Callback(gleam_otp_external:identity(erlang:element(4, Self))),
                    loop(Self);

                {resume, Callback@1} ->
                    Callback@1(),
                    loop({self, running, erlang:element(3, Self), erlang:element(4, Self), erlang:element(5, Self), erlang:element(6, Self), erlang:element(7, Self)});

                {suspend, Callback@2} ->
                    Callback@2(),
                    loop({self, suspended, erlang:element(3, Self), erlang:element(4, Self), erlang:element(5, Self), erlang:element(6, Self), erlang:element(7, Self)});

                {get_status, Callback@3} ->
                    Callback@3(process_status_info(Self)),
                    loop(Self)
            end;

        {unexpected, Message} ->
            logger:warning(unicode:characters_to_list(~"Actor discarding unexpected message: ~s"), [unicode:characters_to_list(gleam@string:inspect(Message))]),
            loop(Self);

        {message, Msg} ->
            case (erlang:element(7, Self))(erlang:element(4, Self), Msg) of
                {stop, Reason} ->
                    exit_process(Reason);

                {continue, State, New_selector} ->
                    Selector = case New_selector of
                        none ->
                            erlang:element(5, Self);

                        {some, S} ->
                            gleam_erlang_ffi:map_selector(S, fun(_value) ->
                                {message, _value}
                            end)
                    end,
                    loop({self, erlang:element(2, Self), erlang:element(3, Self), State, Selector, erlang:element(6, Self), erlang:element(7, Self)})
            end
    end.

-file("src/gleam/otp/actor.gleam", 573).
-spec try_register_self(gleam@erlang@process:name(any())) -> {ok, nil} | {error, binary()}.
try_register_self(Name) ->
    case gleam_erlang_ffi:register_process(erlang:self(), Name) of
        {ok, nil} ->
            {ok, nil};

        {error, _} ->
            {error, ~"name already registered"}
    end.

-file("src/gleam/otp/actor.gleam", 522).
-spec initialise_actor(builder(any(), any(), DZP), gleam@erlang@process:pid_(), gleam@erlang@process:subject({ok, DZP} | {error, binary()})) -> gleam@erlang@process:exit_reason().
initialise_actor(Builder, Parent, Ack) ->
    Result = begin
        gleam@result:'try'(case erlang:element(5, Builder) of
            none ->
                {ok, gleam@erlang@process:new_subject()};

            {some, Name} ->
                gleam@result:'try'(try_register_self(Name), fun(_) ->
                    {ok, gleam@erlang@process:named_subject(Name)}
                end)
        end, fun(Subject) ->
            gleam@result:'try'((erlang:element(2, Builder))(Subject), fun(Result@1) ->
                {ok, {Subject, Result@1}}
            end)
        end)
    end,
    case Result of
        {ok, {Subject, {initialised, State, Selector, Return}}} ->
            Selector@1 = case Selector of
                {some, Selector@2} ->
                    Selector@2;

                none ->
                    _pipe = gleam_erlang_ffi:new_selector(),
                    gleam@erlang@process:select(_pipe, Subject)
            end,
            Selector@3 = gleam_erlang_ffi:map_selector(Selector@1, fun(_value) ->
                {message, _value}
            end),
            gleam@erlang@process:send(Ack, {ok, Return}),
            Self = {self, running, Parent, State, Selector@3, sys:debug_options([]), erlang:element(4, Builder)},
            loop(Self);

        {error, Reason} ->
            gleam@erlang@process:send(Ack, {error, Reason}),
            exit_process(normal)
    end.

-file("src/gleam/otp/actor.gleam", 592).
-spec start(builder(any(), any(), EAC)) -> {ok, started(EAC)} | {error, start_error()}.
-doc(~" Starts an actor from a given `Builder`. On failure, `start` returns a `StartError`").
start(Builder) ->
    Timeout = erlang:element(3, Builder),
    Ack_subject = gleam@erlang@process:new_subject(),
    Self = erlang:self(),
    Child = proc_lib:spawn_link(fun() ->
        initialise_actor(Builder, Self, Ack_subject)
    end),
    Monitor = gleam@erlang@process:monitor(Child),
    Selector = begin
        _pipe = gleam_erlang_ffi:new_selector(),
        _pipe@1 = gleam@erlang@process:select_map(_pipe, Ack_subject, fun(_value) ->
            {ack, _value}
        end),
        gleam@erlang@process:select_specific_monitor(_pipe@1, Monitor, fun(_value@1) ->
            {mon, _value@1}
        end)
    end,
    Result = case gleam_erlang_ffi:select(Selector, Timeout) of
        {ok, {ack, {ok, Subject}}} ->
            {ok, Subject};

        {ok, {ack, {error, Reason}}} ->
            {error, {init_failed, Reason}};

        {ok, {mon, Down}} ->
            {error, {init_exited, erlang:element(4, Down)}};

        {error, nil} ->
            gleam@erlang@process:unlink(Child),
            gleam@erlang@process:kill(Child),
            {error, init_timeout}
    end,
    gleam@erlang@process:demonitor_process(Monitor),
    case Result of
        {ok, Data} ->
            {ok, {started, Child, Data}};

        {error, Error} ->
            {error, Error}
    end.

-file("src/gleam/otp/actor.gleam", 642).
-spec send(gleam@erlang@process:subject(EAJ), EAJ) -> nil.
-doc(~" Send a message over a given channel.

 This is a re-export of `process.send`, for the sake of convenience.
").
send(Subject, Msg) ->
    gleam@erlang@process:send(Subject, Msg).

-file("src/gleam/otp/actor.gleam", 654).
-spec call(gleam@erlang@process:subject(EAL), integer(), fun((gleam@erlang@process:subject(EAN)) -> EAL)) -> EAN.
-doc(~" Send a synchronous message and wait for a response from the receiving
 process.

 If a reply is not received within the given timeout then the sender process
 crashes rather than leaving the processes in an invalid state. 

 This is a re-export of `process.call`, for the sake of convenience.
").
call(Subject, Timeout, Make_message) ->
    gleam@erlang@process:call(Subject, Timeout, Make_message).

