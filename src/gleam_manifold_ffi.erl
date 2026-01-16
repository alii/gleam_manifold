-module(gleam_manifold_ffi).
-export(['receive'/1, 'receive'/2, create_atom/1, dynamic_atom/1, dynamic_nil/0]).

'receive'({tag, Ref}) ->
    receive
        {Ref, Message} -> Message
    end.

'receive'({tag, Ref}, Timeout) ->
    receive
        {Ref, Message} -> {ok, Message}
    after Timeout ->
        {error, nil}
    end.

create_atom(Binary) when is_binary(Binary) ->
    binary_to_atom(Binary, utf8).

dynamic_atom(Atom) when is_atom(Atom) ->
    Atom.

dynamic_nil() ->
    nil.
