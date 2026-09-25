-module(watershed_container_ffi).
-export([valid_service_url/1]).

valid_service_url(Url) ->
    case uri_string:parse(Url) of
        Parts when is_map(Parts) -> true;
        {error, _, _} -> false
    end.
