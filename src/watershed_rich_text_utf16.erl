-module(watershed_rich_text_utf16).
-export([length/1, valid/1, boundary/2, slice/3]).

length(Value) -> count(unicode:characters_to_list(Value)).
count([]) -> 0;
count([Codepoint | Rest]) when Codepoint > 16#FFFF -> 2 + count(Rest);
count([_ | Rest]) -> 1 + count(Rest).

%% Gleam strings on BEAM are valid UTF-8 binaries, so no lone surrogate can
%% inhabit one. This function mirrors the JavaScript FFI contract.
valid(_Value) -> true.

boundary(Value, Offset) when Offset >= 0 ->
  boundary_chars(unicode:characters_to_list(Value), Offset);
boundary(_Value, _Offset) -> false.
boundary_chars([], 0) -> true;
boundary_chars([], _Offset) -> false;
boundary_chars([Codepoint | Rest], Offset) ->
  Width = if Codepoint > 16#FFFF -> 2; true -> 1 end,
  case Offset of
    0 -> true;
    Width -> boundary_chars(Rest, 0);
    _ when Offset > Width -> boundary_chars(Rest, Offset - Width);
    _ -> false
  end.

slice(Value, Start, Size) ->
  Chars = unicode:characters_to_list(Value),
  unicode:characters_to_binary(take_units(drop_units(Chars, Start), Size)).
drop_units(Chars, 0) -> Chars;
drop_units([Codepoint | Rest], Count) ->
  Width = if Codepoint > 16#FFFF -> 2; true -> 1 end,
  drop_units(Rest, Count - Width);
drop_units([], _Count) -> [].
take_units(_Chars, 0) -> [];
take_units([Codepoint | Rest], Count) ->
  Width = if Codepoint > 16#FFFF -> 2; true -> 1 end,
  [Codepoint | take_units(Rest, Count - Width)];
take_units([], _Count) -> [].
