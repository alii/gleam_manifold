//// Gleam bindings to Discord's Manifold library
////
//// More information about Manifold can be found on its
//// [GitHub page](https://github.com/discord/manifold).
////
//// Unlike Gleam's erlang module, Tags in gleam_manifold
//// are not bound to a specific process. They're merely a unique
//// reference which provides runtime guarantees about type-safe
//// message delivery.

import gleam/erlang/process
import gleam/erlang/reference
import gleam/list

pub opaque type Tag(message) {
  Tag(ref: reference.Reference)
}

type Message(message) =
  #(reference.Reference, message)

/// Pack mode determines how messages are serialized before sending
pub type PackMode {
  /// Pack messages as binary using term_to_binary
  Binary
  /// Use Erlang Term Format (default)
  Etf
  /// No special packing
  NoPacking
}

/// Send mode determines how messages are sent
pub type SendMode {
  /// Route messages through a sender process (non-blocking)
  Offload
  /// Send directly (default)
  Direct
}

/// Options for configuring message sending behavior
pub type ManifoldOption {
  PackModeOption(PackMode)
  SendModeOption(SendMode)
}

/// Create a new Manifold tag for sending and receiving messages
/// of the specified type.
pub fn new_tag() -> Tag(message) {
  Tag(reference.new())
}

pub fn send(
  pid: process.Pid,
  tag: Tag(message),
  message: message,
) -> Nil {
  manifold_send(pid, #(tag.ref, message))
  Nil
}

pub fn send_with_options(
  pid: process.Pid,
  tag: Tag(message),
  message: message,
  options: List(ManifoldOption),
) -> Nil {
  let opts = options_to_keyword_list(options)
  manifold_send_with_options(pid, #(tag.ref, message), opts)
  Nil
}

pub fn send_multi(
  pids: List(process.Pid),
  tag: Tag(message),
  message: message,
) -> Nil {
  manifold_send_multi(pids, #(tag.ref, message))
  Nil
}

pub fn send_multi_with_options(
  pids: List(process.Pid),
  tag: Tag(message),
  message: message,
  options: List(ManifoldOption),
) -> Nil {
  let opts = options_to_keyword_list(options)
  manifold_send_multi_with_options(pids, #(tag.ref, message), opts)
  Nil
}

@external(erlang, "gleam_manifold_ffi", "receive")
pub fn receive(tag: Tag(message), timeout: Int) -> Result(message, Nil)

@external(erlang, "gleam_manifold_ffi", "receive")
pub fn receive_forever(tag: Tag(message)) -> message

/// Set a custom partitioner key for the current process.
/// This controls which partitioner process will handle your messages,
/// useful for load balancing and ensuring message ordering.
pub fn set_partitioner_key(key: String) -> Nil {
  do_set_partitioner_key(key)
  Nil
}

/// Set a custom sender key for the current process.
/// This controls which sender process will handle offloaded messages.
pub fn set_sender_key(key: String) -> Nil {
  do_set_sender_key(key)
  Nil
}

fn options_to_keyword_list(options: List(ManifoldOption)) -> List(#(Atom, Term)) {
  list.map(options, fn(opt) {
    case opt {
      PackModeOption(Binary) -> #(
        create_atom("pack_mode"),
        dynamic_atom(create_atom("binary")),
      )
      PackModeOption(Etf) -> #(
        create_atom("pack_mode"),
        dynamic_atom(create_atom("etf")),
      )
      PackModeOption(NoPacking) -> #(create_atom("pack_mode"), dynamic_nil())
      SendModeOption(Offload) -> #(
        create_atom("send_mode"),
        dynamic_atom(create_atom("offload")),
      )
      SendModeOption(Direct) -> #(create_atom("send_mode"), dynamic_nil())
    }
  })
}

type Term

type Atom

type DoNotLeak

@external(erlang, "gleam_manifold_ffi", "create_atom")
fn create_atom(name: String) -> Atom

@external(erlang, "gleam_manifold_ffi", "dynamic_atom")
fn dynamic_atom(atom: Atom) -> Term

@external(erlang, "gleam_manifold_ffi", "dynamic_nil")
fn dynamic_nil() -> Term

@external(erlang, "Elixir.Manifold", "send")
fn manifold_send(pid: process.Pid, message: Message(message)) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "send")
fn manifold_send_multi(
  pids: List(process.Pid),
  message: Message(message),
) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "send")
fn manifold_send_with_options(
  pid: process.Pid,
  message: Message(message),
  options: List(#(Atom, Term)),
) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "send")
fn manifold_send_multi_with_options(
  pids: List(process.Pid),
  message: Message(message),
  options: List(#(Atom, Term)),
) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "set_partitioner_key")
fn do_set_partitioner_key(key: String) -> DoNotLeak

@external(erlang, "Elixir.Manifold", "set_sender_key")
fn do_set_sender_key(key: String) -> DoNotLeak
