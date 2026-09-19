-module(gleam@otp@system).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([debug_state/1, get_state/1, suspend/1, resume/1]).
-export_type([mode/0, debug_option/0, debug_state/0, status_info/0, system_message/0, do_not_leak/0]).

-type mode() :: running | suspended.

-type debug_option() :: no_debug.

-type debug_state() :: any().

-type status_info() :: {status_info, gleam@erlang@atom:atom_(), gleam@erlang@process:pid_(), mode(), debug_state(), gleam@dynamic:dynamic_()}.

-type system_message() :: {resume, fun(() -> nil)} | {suspend, fun(() -> nil)} | {get_state, fun((gleam@dynamic:dynamic_()) -> nil)} | {get_status, fun((status_info()) -> nil)}.

-type do_not_leak() :: any().

-file("src/gleam/otp/system.gleam", 19).
-spec debug_state(list(debug_option())) -> debug_state().
debug_state(A) ->
    sys:debug_options(A).

-file("src/gleam/otp/system.gleam", 65).
-spec get_state(gleam@erlang@process:pid_()) -> gleam@dynamic:dynamic_().
-doc(~" Get the state of a given OTP compatible process. This function is only
 intended for debugging.

 Requires Erlang/OTP 26.1 or newer, as the underlying interface changed
 in [OTP-18633][1] from a literal type to a result type.

 For more information see the [Erlang documentation][2].

 [1]: https://www.erlang.org/patches/otp-26.1#stdlib-5.1
 [2]: https://erlang.org/doc/man/sys.html#get_state-1
").
get_state(From) ->
    sys:get_state(From).

-file("src/gleam/otp/system.gleam", 77).
-spec suspend(gleam@erlang@process:pid_()) -> nil.
-doc(~" Request an OTP compatible process to suspend, causing it to only handle
 system messages.

 For more information see the [Erlang documentation][1].

 [1]: https://erlang.org/doc/man/sys.html#suspend-1
").
suspend(Pid) ->
    sys:suspend(Pid),
    nil.

-file("src/gleam/otp/system.gleam", 92).
-spec resume(gleam@erlang@process:pid_()) -> nil.
-doc(~" Request a suspended OTP compatible process to resume, causing it to handle
 all messages rather than only system messages.

 For more information see the [Erlang documentation][1].

 [1]: https://erlang.org/doc/man/sys.html#resume-1
").
resume(Pid) ->
    sys:resume(Pid),
    nil.

