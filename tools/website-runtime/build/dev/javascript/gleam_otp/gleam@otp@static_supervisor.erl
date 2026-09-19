-module(gleam@otp@static_supervisor).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/1, restart_tolerance/3, auto_shutdown/2, start/1, supervised/1, add/2, init/1, start_child_callback/1]).
-export_type([supervisor/0, strategy/0, auto_shutdown/0, builder/0, erlang_start_flags/0, erlang_start_flag/1, erlang_child_spec/0, erlang_child_spec_property/1, timeout_/0]).
-moduledoc(~" A supervisor where the number and types of the children are specified
 once, and the supervisor manages them using a configured restart strategy.

 For further detail see the Erlang documentation:
 <https://www.erlang.org/doc/apps/stdlib/supervisor.html>.

 # Example

 ```gleam
 import gleam/otp/actor
 import gleam/otp/static_supervisor.{type Supervisor} as supervisor
 import app/database_pool
 import app/http_server
 
 pub fn start_supervisor() -> actor.StartResult(Supervisor) {
   supervisor.new(supervisor.OneForOne)
   |> supervisor.add(database_pool.supervised())
   |> supervisor.add(http_server.supervised())
   |> supervisor.start
 }
 ```").

-opaque supervisor() :: {supervisor, gleam@erlang@process:pid_()}.

-type strategy() :: one_for_one | one_for_all | rest_for_one.

-type auto_shutdown() :: never | any_significant | all_significant.

-opaque builder() :: {builder, strategy(), integer(), integer(), auto_shutdown(), list(gleam@otp@supervision:child_specification(nil))}.

-type erlang_start_flags() :: any().

-type erlang_start_flag(FBY) :: {strategy, strategy()} | {intensity, integer()} | {period, integer()} | {auto_shutdown, auto_shutdown()} | {gleam_phantom, FBY}.

-type erlang_child_spec() :: any().

-type erlang_child_spec_property(FBZ) :: {id, integer()} | {start, {gleam@erlang@atom:atom_(), gleam@erlang@atom:atom_(), list(fun(() -> {ok, gleam@otp@actor:started(FBZ)} | {error, gleam@otp@actor:start_error()}))}} | {restart, gleam@otp@supervision:restart()} | {significant, boolean()} | {type, gleam@erlang@atom:atom_()} | {shutdown, timeout_()}.

-type timeout_() :: any().

-file("src/gleam/otp/static_supervisor.gleam", 110).
-spec new(strategy()) -> builder().
-doc(~" Create a new supervisor builder, ready for further configuration.
").
new(Strategy) ->
    {builder, Strategy, 2, 5, never, []}.

-file("src/gleam/otp/static_supervisor.gleam", 131).
-spec restart_tolerance(builder(), integer(), integer()) -> builder().
-doc(~" To prevent a supervisor from getting into an infinite loop of child
 process terminations and restarts, a maximum restart tolerance is
 defined using two integer values specified with keys intensity and
 period in the above map. Assuming the values MaxR for intensity and MaxT
 for period, then, if more than MaxR restarts occur within MaxT seconds,
 the supervisor terminates all child processes and then itself. The
 termination reason for the supervisor itself in that case will be
 shutdown. 

 Intensity defaults to 2 and period defaults to 5.
").
restart_tolerance(Builder, Intensity, Period) ->
    {builder, erlang:element(2, Builder), Intensity, Period, erlang:element(5, Builder), erlang:element(6, Builder)}.

-file("src/gleam/otp/static_supervisor.gleam", 142).
-spec auto_shutdown(builder(), auto_shutdown()) -> builder().
-doc(~" A supervisor can be configured to automatically shut itself down with
 exit reason shutdown when significant children terminate.
").
auto_shutdown(Builder, Value) ->
    {builder, erlang:element(2, Builder), erlang:element(3, Builder), erlang:element(4, Builder), Value, erlang:element(6, Builder)}.

-file("src/gleam/otp/static_supervisor.gleam", 209).
-spec convert_child(gleam@otp@supervision:child_specification(any()), integer()) -> erlang_child_spec().
convert_child(Child, Id) ->
    Mfa = {erlang:binary_to_atom(~"gleam@otp@static_supervisor"), erlang:binary_to_atom(~"start_child_callback"), [erlang:element(2, Child)]},
    {Type_, Shutdown} = case erlang:element(5, Child) of
        supervisor ->
            {erlang:binary_to_atom(~"supervisor"), gleam_otp_external:make_timeout(-1)};

        {worker, Ms} ->
            {erlang:binary_to_atom(~"worker"), gleam_otp_external:make_timeout(Ms)}
    end,
    maps:from_list([{id, Id}, {start, Mfa}, {restart, erlang:element(3, Child)}, {significant, erlang:element(4, Child)}, {type, Type_}, {shutdown, Shutdown}]).

-file("src/gleam/otp/static_supervisor.gleam", 159).
-spec start(builder()) -> {ok, gleam@otp@actor:started(supervisor())} | {error, gleam@otp@actor:start_error()}.
-doc(~" Start a new supervisor process with the configuration and children
 specified within the builder.

 Typically you would use the `supervised` function to add your supervisor to
 a supervision tree instead of using this function directly.

 The supervisor will be linked to the parent process that calls this
 function.

 If any child fails to start the supervisor first terminates all already
 started child processes with reason shutdown and then terminate itself and
 returns an error.
").
start(Builder) ->
    Flags = maps:from_list([{strategy, erlang:element(2, Builder)}, {intensity, erlang:element(3, Builder)}, {period, erlang:element(4, Builder)}, {auto_shutdown, erlang:element(5, Builder)}]),
    Module = erlang:binary_to_atom(~"gleam@otp@static_supervisor"),
    Children = begin
        _pipe = erlang:element(6, Builder),
        _pipe@1 = lists:reverse(_pipe),
        gleam@list:index_map(_pipe@1, fun convert_child/2)
    end,
    case supervisor:start_link(Module, {Flags, Children}) of
        {ok, Pid} ->
            {ok, {started, Pid, {supervisor, Pid}}};

        {error, Error} ->
            {error, gleam_otp_external:convert_erlang_start_error(Error)}
    end.

-file("src/gleam/otp/static_supervisor.gleam", 188).
-spec supervised(builder()) -> gleam@otp@supervision:child_specification(supervisor()).
-doc(~" Create a `ChildSpecification` that adds this supervisor as the child of
 another, making it fault tolerant and part of the application's supervision
 tree. You should prefer this to starting unsupervised supervisors with the
 `start` function.

 If any child fails to start the supervisor first terminates all already
 started child processes with reason shutdown and then terminate itself and
 returns an error.
").
supervised(Builder) ->
    gleam@otp@supervision:supervisor(fun() ->
        start(Builder)
    end).

-file("src/gleam/otp/static_supervisor.gleam", 202).
-spec add(builder(), gleam@otp@supervision:child_specification(any())) -> builder().
-doc(~" Add a child to the supervisor.").
add(Builder, Child) ->
    {builder, erlang:element(2, Builder), erlang:element(3, Builder), erlang:element(4, Builder), erlang:element(5, Builder), [gleam@otp@supervision:map_data(Child, fun(_) ->
        nil
    end) | erlang:element(6, Builder)]}.

-file("src/gleam/otp/static_supervisor.gleam", 271).
-spec init(gleam@dynamic:dynamic_()) -> {ok, gleam@dynamic:dynamic_()} | {error, any()}.
-doc(false).
init(Start_data) ->
    {ok, Start_data}.

-file("src/gleam/otp/static_supervisor.gleam", 277).
-spec start_child_callback(fun(() -> {ok, gleam@otp@actor:started(any())} | {error, gleam@otp@actor:start_error()})) -> {ok, gleam@erlang@process:pid_()} | {error, gleam@otp@actor:start_error()}.
-doc(false).
start_child_callback(Start) ->
    case Start() of
        {ok, Started} ->
            {ok, erlang:element(2, Started)};

        {error, Error} ->
            {error, Error}
    end.

