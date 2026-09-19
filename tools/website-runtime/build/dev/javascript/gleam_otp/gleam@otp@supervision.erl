-module(gleam@otp@supervision).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([worker/1, supervisor/1, significant/2, timeout/2, restart/2, map_data/2]).
-export_type([restart/0, child_type/0, child_specification/1]).

-type restart() :: permanent | transient | temporary.

-type child_type() :: {worker, integer()} | supervisor.

-type child_specification(ENZ) :: {child_specification, fun(() -> {ok, gleam@otp@actor:started(ENZ)} | {error, gleam@otp@actor:start_error()}), restart(), boolean(), child_type()}.

-file("src/gleam/otp/supervision.gleam", 61).
-spec worker(fun(() -> {ok, gleam@otp@actor:started(EOA)} | {error, gleam@otp@actor:start_error()})) -> child_specification(EOA).
-doc(~" A regular child process.

 You should use this unless your process is also a supervisor.

 The default shutdown timeout is 5000ms. This can be changed with the
 `timeout` function.
").
worker(Start) ->
    {child_specification, Start, permanent, false, {worker, 5000}}.

-file("src/gleam/otp/supervision.gleam", 76).
-spec supervisor(fun(() -> {ok, gleam@otp@actor:started(EOF)} | {error, gleam@otp@actor:start_error()})) -> child_specification(EOF).
-doc(~" A special child that is a supervisor itself.

 Supervisor children have an unlimited shutdown time, there is no timeout.
").
supervisor(Start) ->
    {child_specification, Start, permanent, false, supervisor}.

-file("src/gleam/otp/supervision.gleam", 96).
-spec significant(child_specification(EOK), boolean()) -> child_specification(EOK).
-doc(~" This defines if a child is considered significant for automatic
 self-shutdown of the supervisor.

 You most likely do not want to consider any children significant.

 This will be ignored if the supervisor auto shutdown is set to `Never`,
 which is the default.

 The default value for significance is `False`.").
significant(Child, Significant) ->
    {child_specification, erlang:element(2, Child), erlang:element(3, Child), Significant, erlang:element(5, Child)}.

-file("src/gleam/otp/supervision.gleam", 110).
-spec timeout(child_specification(EON), integer()) -> child_specification(EON).
-doc(~" This defines the amount of milliseconds a child has to shut down before
 being brutal killed by the supervisor.

 If not set the default for a child is 5000ms.

 This will be ignored if the child is a supervisor itself.
").
timeout(Child, Ms) ->
    case erlang:element(5, Child) of
        {worker, _} ->
            {child_specification, erlang:element(2, Child), erlang:element(3, Child), erlang:element(4, Child), {worker, Ms}};

        _ ->
            Child
    end.

-file("src/gleam/otp/supervision.gleam", 124).
-spec restart(child_specification(EOQ), restart()) -> child_specification(EOQ).
-doc(~" When the child is to be restarted. See the `Restart` documentation for
 more.

 The default value for restart is `Permanent`.").
restart(Child, Restart) ->
    {child_specification, erlang:element(2, Child), Restart, erlang:element(4, Child), erlang:element(5, Child)}.

-file("src/gleam/otp/supervision.gleam", 133).
-spec map_data(child_specification(EOT), fun((EOT) -> EOV)) -> child_specification(EOV).
-doc(~" Transform the data of the started child process.
").
map_data(Child, Transform) ->
    {child_specification, fun() ->
        case (erlang:element(2, Child))() of
            {ok, Started} ->
                {ok, {started, erlang:element(2, Started), Transform(erlang:element(3, Started))}};

            {error, E} ->
                {error, E}
        end
    end, erlang:element(3, Child), erlang:element(4, Child), erlang:element(5, Child)}.

