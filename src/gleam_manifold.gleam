//// Gleam bindings to Discord's [Manifold](https://github.com/discord/manifold),
//// a library for sending the same message to many processes quickly.
////
//// Manifold is a faster `process.send`. Create a `Channel`, receive from it in
//// as many processes as you like, and `broadcast` one message to all of them in
//// a single call.

import gleam/dynamic.{type Dynamic}
import gleam/erlang/process.{type Pid, type Selector}
import gleam/erlang/reference.{type Reference}
import gleam/function

// Channels --------------------------------------------------------------------

/// A typed address that messages can be sent to through Manifold, along with
/// the options used when sending to it.
///
/// This is Manifold's counterpart to `process.Subject`. The difference is that
/// it is not tied to one owning process: any number of processes can receive
/// from the same channel, which is what lets `broadcast` deliver a single
/// message to all of them in one call. Because of that, a pid is passed when
/// sending rather than being carried by the channel.
///
pub opaque type Channel(message) {
  Channel(
    reference: Reference,
    pack_mode: PackMode,
    send_mode: SendMode,
    options: SendOptions,
  )
}

/// The tuple Manifold places in a receiving process' mailbox.
type Envelope(message) =
  #(Reference, message)

/// The keyword list of options Manifold expects. Each one is an Erlang literal
/// living in the FFI module's constant pool, so selecting the right list costs
/// nothing and no atoms are created at runtime.
type SendOptions

/// Create a new channel, sending with Manifold's defaults.
///
/// Tune it by piping through `pack` and `send_mode`:
///
/// ```gleam
/// let channel =
///   manifold.new_channel()
///   |> manifold.pack(manifold.Binary)
///   |> manifold.send_mode(manifold.Offload)
/// ```
///
pub fn new_channel() -> Channel(message) {
  build(reference.new(), Etf, Direct)
}

// Options ---------------------------------------------------------------------

/// How a message is packed before being sent.
///
/// This only has an effect when broadcasting to two or more processes. Manifold
/// sends a message bound for a single process as a plain term whatever this is
/// set to.
///
pub type PackMode {
  /// Serialise the message once with `term_to_binary` before dispatching it.
  /// Cheaper when sending a large message to many nodes, as the term is
  /// serialised once rather than once per receiving node.
  Binary
  /// Send the message as a plain term, with no packing. Manifold's default.
  Etf
}

/// Whether sending happens on the calling process or is handed off to another.
///
pub type SendMode {
  /// Hand the message to a sender process so that sending never blocks the
  /// caller.
  Offload
  /// Send from the calling process. Manifold's default.
  Direct
}

/// Set how messages sent to this channel are packed.
///
/// This returns a copy of the channel that shares its reference, so the copy is
/// received by exactly the same processes. That makes overriding the mode for a
/// single send safe:
///
/// ```gleam
/// // everyone receiving from `channel` still gets this
/// manifold.broadcast(channel |> manifold.pack(manifold.Etf), to: pids, message: m)
/// ```
///
pub fn pack(channel: Channel(message), mode: PackMode) -> Channel(message) {
  build(channel.reference, mode, channel.send_mode)
}

/// Set whether sending to this channel is offloaded to a sender process.
///
/// Like `pack`, this returns a copy sharing the channel's reference.
///
pub fn send_mode(
  channel: Channel(message),
  mode: SendMode,
) -> Channel(message) {
  build(channel.reference, channel.pack_mode, mode)
}

fn build(
  reference: Reference,
  pack_mode: PackMode,
  send_mode: SendMode,
) -> Channel(message) {
  // Chosen here, once, so that sending only has to pass the list along.
  let options = case pack_mode, send_mode {
    Binary, Offload -> binary_offload_options()
    Binary, Direct -> binary_options()
    Etf, Offload -> offload_options()
    Etf, Direct -> default_options()
  }

  Channel(reference:, pack_mode:, send_mode:, options:)
}

// Sending ---------------------------------------------------------------------

/// Send a message to a single process.
///
/// A channel's `PackMode` has no effect here: Manifold never packs a message
/// bound for a single process.
///
pub fn send(
  channel: Channel(message),
  to pid: Pid,
  message message: message,
) -> Nil {
  manifold_send(pid, #(channel.reference, message), channel.options)
  Nil
}

/// Send the same message to many processes at once.
///
/// This is what Manifold exists for. Rather than sending to each process in
/// turn, the message is dispatched to one partitioner per node, which fans it
/// out from there.
///
pub fn broadcast(
  channel: Channel(message),
  to pids: List(Pid),
  message message: message,
) -> Nil {
  manifold_broadcast(pids, #(channel.reference, message), channel.options)
  Nil
}

// Receiving -------------------------------------------------------------------

/// Wait for a message on the channel, giving up after `timeout` milliseconds.
///
/// Any process can call this. Unlike `process.receive` there is no owner to
/// check against, because a Manifold channel has no single owning process.
///
pub fn receive(
  from channel: Channel(message),
  within timeout: Int,
) -> Result(message, Nil) {
  do_receive(channel.reference, timeout)
}

/// Wait for a message on the channel, blocking forever.
///
pub fn receive_forever(from channel: Channel(message)) -> message {
  do_receive_forever(channel.reference)
}

/// A `Selector` that receives from this channel, for a process that waits on
/// one channel and nothing else.
///
/// Build it once, outside your receive loop: each call allocates a new selector.
///
pub fn selector(channel: Channel(message)) -> Selector(message) {
  process.new_selector() |> select(channel)
}

/// Add a channel to an existing `Selector`, so a process can wait on it
/// alongside its own `process.Subject`s, monitors and timers.
///
pub fn select(
  selector: Selector(message),
  for channel: Channel(message),
) -> Selector(message) {
  select_map(selector, channel, function.identity)
}

/// Add a channel to a `Selector`, converting its messages into the selector's
/// message type. Use this when one process waits on sources of differing types.
///
/// ```gleam
/// type Message {
///   Broadcast(String)
///   Shutdown
/// }
///
/// process.new_selector()
/// |> process.select(commands)
/// |> manifold.select_map(channel, Broadcast)
/// ```
///
pub fn select_map(
  selector: Selector(payload),
  for channel: Channel(message),
  mapping transform: fn(message) -> payload,
) -> Selector(payload) {
  // Manifold delivers `#(reference, message)`: a tuple tagged with the
  // channel's reference, holding one field after that tag.
  process.select_record(selector, channel.reference, 1, apply_to_payload(
    transform,
    _,
  ))
}

// Routing ---------------------------------------------------------------------

/// Set the partitioner key for the calling process.
///
/// Messages sent by this process are routed through the partitioner this key
/// hashes to. Two processes sharing a key share a partitioner, so their messages
/// to a given node stay ordered relative to one another.
///
/// This is process wide: it affects every subsequent Manifold send from this
/// process, on any channel.
///
pub fn set_partitioner_key(key: String) -> Nil {
  manifold_set_partitioner_key(key)
  Nil
}

/// Set the sender key for the calling process.
///
/// Like `set_partitioner_key`, but for the sender process used by `Offload`,
/// and likewise process wide.
///
pub fn set_sender_key(key: String) -> Nil {
  manifold_set_sender_key(key)
  Nil
}

// Externals -------------------------------------------------------------------

type DoNotLeak

/// `select_record` hands its mapping function the whole message as a `Dynamic`,
/// and a Manifold payload is an arbitrary Gleam value with no decoder, so the
/// payload has to be taken on trust somewhere. It is taken in Erlang, where the
/// clause pattern matches the envelope and so at least checks its shape.
///
@external(erlang, "gleam_manifold_ffi", "apply_to_payload")
fn apply_to_payload(
  transform: fn(message) -> payload,
  envelope: Dynamic,
) -> payload

@external(erlang, "gleam_manifold_ffi", "receive")
fn do_receive(reference: Reference, timeout: Int) -> Result(message, Nil)

@external(erlang, "gleam_manifold_ffi", "receive")
fn do_receive_forever(reference: Reference) -> message

@external(erlang, "gleam_manifold_ffi", "default_options")
fn default_options() -> SendOptions

@external(erlang, "gleam_manifold_ffi", "binary_options")
fn binary_options() -> SendOptions

@external(erlang, "gleam_manifold_ffi", "offload_options")
fn offload_options() -> SendOptions

@external(erlang, "gleam_manifold_ffi", "binary_offload_options")
fn binary_offload_options() -> SendOptions

@external(erlang, "Elixir.Manifold", "send")
fn manifold_send(
  pid: Pid,
  envelope: Envelope(message),
  options: SendOptions,
) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "send")
fn manifold_broadcast(
  pids: List(Pid),
  envelope: Envelope(message),
  options: SendOptions,
) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "set_partitioner_key")
fn manifold_set_partitioner_key(key: String) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "set_sender_key")
fn manifold_set_sender_key(key: String) -> DoNotLeak
