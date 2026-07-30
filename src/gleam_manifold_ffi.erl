-module(gleam_manifold_ffi).
-export([
    'receive'/1,
    'receive'/2,
    apply_to_payload/2,
    default_options/0,
    binary_options/0,
    offload_options/0,
    binary_offload_options/0
]).

'receive'(Reference) ->
    receive
        {Reference, Message} -> Message
    end.

'receive'(Reference, Timeout) ->
    receive
        {Reference, Message} -> {ok, Message}
    after Timeout ->
        {error, nil}
    end.

%% Called by the selector with the whole envelope. Matching `{_, Payload}` here
%% means a message of the wrong shape crashes at this boundary rather than being
%% handed onwards as a value of a type it does not have.
apply_to_payload(Transform, {_Reference, Payload}) ->
    Transform(Payload).

%% Manifold's send options.
%%
%% These are written as literals so the compiler places them in the module's
%% constant pool, making them free to return. Building the same lists in Gleam
%% would call binary_to_atom for every atom, every time a channel is built.
%%
%% Manifold reads these with Keyword.get and treats a missing key as the
%% default, so each default is expressed by leaving its key out entirely. Doing
%% otherwise would fail Manifold's own valid_send_options?/1.
default_options() ->
    [].

binary_options() ->
    [{pack_mode, binary}].

offload_options() ->
    [{send_mode, offload}].

binary_offload_options() ->
    [{pack_mode, binary}, {send_mode, offload}].
