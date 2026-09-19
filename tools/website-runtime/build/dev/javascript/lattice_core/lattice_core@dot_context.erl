-module(lattice_core@dot_context).
-compile([no_auto_import, nowarn_ignored, nowarn_unused_vars, nowarn_unused_function, nowarn_nomatch, inline]).
-export([new/0, add_dot/3, remove_dots/2, contains_dots/2]).
-export_type([dot/0, dot_context/0]).
-moduledoc(~" A dot context tracks observed events (dots) across replicas.

 A \"dot\" is a pair of (replica_id, counter) uniquely identifying a single
 write event. The dot context is used by causal CRDTs like MV-Register and
 OR-Set to determine which operations have been observed and which can be
 safely discarded during merge.

 ## Example

 ```gleam
 import lattice_core/dot_context.{Dot}
 import lattice_core/replica_id

 let node_a = replica_id.new(\"node-a\")
 let node_b = replica_id.new(\"node-b\")
 let ctx = dot_context.new()
   |> dot_context.add_dot(node_a, 1)
   |> dot_context.add_dot(node_b, 1)
 dot_context.contains_dots(ctx, [Dot(node_a, 1)])  // -> True
 ```").

-type dot() :: {dot, lattice_core@replica_id:replica_id(), integer()}.

-opaque dot_context() :: {dot_context, gleam@set:set(dot())}.

-file("src/lattice_core/dot_context.gleam", 48).
-spec new() -> dot_context().
-doc(~" Create a new empty DotContext.

 Returns a context with no observed dots. Use `add_dot` to record events.").
new() ->
    {dot_context, gleam@set:new()}.

-file("src/lattice_core/dot_context.gleam", 56).
-spec add_dot(dot_context(), lattice_core@replica_id:replica_id(), integer()) -> dot_context().
-doc(~" Add a specific dot to the context.

 Records that the event `(replica_id, counter)` has been observed. If the
 dot is already present, the context is returned unchanged.").
add_dot(Context, Replica_id, Counter) ->
    {dot_context, gleam@set:insert(erlang:element(2, Context), {dot, Replica_id, Counter})}.

-file("src/lattice_core/dot_context.gleam", 68).
-spec remove_dots(dot_context(), list(dot())) -> dot_context().
-doc(~" Remove a list of dots from the context.

 Returns a new context with all dots in `dots` removed. Dots that are not
 present are silently ignored.").
remove_dots(Context, Dots) ->
    {dot_context, gleam@list:fold(Dots, erlang:element(2, Context), fun(Acc, Dot) ->
        gleam@set:delete(Acc, Dot)
    end)}.

-file("src/lattice_core/dot_context.gleam", 79).
-spec contains_dots(dot_context(), list(dot())) -> boolean().
-doc(~" Check if all given dots are present in the context.

 Returns `True` only if every dot in `dots` has been observed (i.e., every
 dot was previously added via `add_dot` and not subsequently removed).
 Returns `True` for an empty `dots` list.").
contains_dots(Context, Dots) ->
    gleam@list:all(Dots, fun(Dot) ->
        gleam@set:contains(erlang:element(2, Context), Dot)
    end).

