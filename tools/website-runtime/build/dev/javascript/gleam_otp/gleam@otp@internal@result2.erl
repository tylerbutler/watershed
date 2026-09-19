-module(gleam@otp@internal@result2).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export_type([result2/3]).
-moduledoc(false).

-type result2(ENV, ENW, ENX) :: {ok, ENV, ENW} | {error, ENX}.

