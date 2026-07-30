import gleam/erlang/process
import gleam_manifold as manifold
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

/// Spawn a process that waits for one message on `channel` and echoes it back
/// to `parent` on the same channel.
fn spawn_echo(
  channel: manifold.Channel(String),
  parent: process.Pid,
) -> process.Pid {
  process.spawn(fn() {
    let assert Ok(message) = manifold.receive(channel, 100)
    manifold.send(channel, to: parent, message: message)
  })
}

pub fn send_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  process.spawn(fn() {
    manifold.send(channel, to: parent, message: "Hello world")
  })

  assert manifold.receive(channel, 100) == Ok("Hello world")
}

pub fn send_to_many_pids_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  let a = spawn_echo(channel, parent)
  let b = spawn_echo(channel, parent)

  manifold.send(channel, to: a, message: "hello from a")
  manifold.send(channel, to: b, message: "hello from b")

  assert manifold.receive(channel, 100) == Ok("hello from a")
  assert manifold.receive(channel, 100) == Ok("hello from b")
  assert manifold.receive(channel, 5) == Error(Nil)
}

pub fn broadcast_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  let a = spawn_echo(channel, parent)
  let b = spawn_echo(channel, parent)

  manifold.broadcast(channel, to: [a, b], message: "hello from both")

  assert manifold.receive(channel, 100) == Ok("hello from both")
  assert manifold.receive(channel, 100) == Ok("hello from both")
  assert manifold.receive(channel, 5) == Error(Nil)
}

pub fn receive_forever_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  process.spawn(fn() {
    manifold.send(channel, to: parent, message: "Forever message")
  })

  assert manifold.receive_forever(channel) == "Forever message"
}

pub fn channels_do_not_cross_test() {
  let a = manifold.new_channel()
  let b = manifold.new_channel()
  let parent = process.self()

  manifold.send(a, to: parent, message: "for a")

  assert manifold.receive(b, 5) == Error(Nil)
  assert manifold.receive(a, 5) == Ok("for a")
}

pub fn any_process_can_receive_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  // The channel was created here but is received from in the spawned process,
  // which a `process.Subject` would panic on.
  let receiver = spawn_echo(channel, parent)

  manifold.send(channel, to: receiver, message: "received elsewhere")

  assert manifold.receive(channel, 100) == Ok("received elsewhere")
}

// Options ---------------------------------------------------------------------

pub fn pack_binary_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Binary)
  let parent = process.self()

  let a = spawn_echo(channel, parent)
  let b = spawn_echo(channel, parent)

  manifold.broadcast(channel, to: [a, b], message: "packed")

  assert manifold.receive(channel, 100) == Ok("packed")
  assert manifold.receive(channel, 100) == Ok("packed")
}

pub fn pack_etf_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Etf)
  let parent = process.self()

  let a = spawn_echo(channel, parent)

  manifold.broadcast(channel, to: [a], message: "etf")

  assert manifold.receive(channel, 100) == Ok("etf")
}

pub fn offload_test() {
  let channel = manifold.new_channel() |> manifold.send_mode(manifold.Offload)
  let parent = process.self()

  process.spawn(fn() {
    manifold.send(channel, to: parent, message: "offloaded")
  })

  assert manifold.receive(channel, 100) == Ok("offloaded")
}

pub fn direct_test() {
  let channel = manifold.new_channel() |> manifold.send_mode(manifold.Direct)
  let parent = process.self()

  process.spawn(fn() { manifold.send(channel, to: parent, message: "direct") })

  assert manifold.receive(channel, 100) == Ok("direct")
}

pub fn combined_options_test() {
  let channel =
    manifold.new_channel()
    |> manifold.pack(manifold.Binary)
    |> manifold.send_mode(manifold.Offload)

  let parent = process.self()

  let a = spawn_echo(channel, parent)
  let b = spawn_echo(channel, parent)

  manifold.broadcast(channel, to: [a, b], message: "both options")

  assert manifold.receive(channel, 100) == Ok("both options")
  assert manifold.receive(channel, 100) == Ok("both options")
}

pub fn setting_an_option_twice_keeps_the_last_test() {
  let channel =
    manifold.new_channel()
    |> manifold.pack(manifold.Binary)
    |> manifold.pack(manifold.Etf)

  let parent = process.self()
  let a = spawn_echo(channel, parent)

  manifold.broadcast(channel, to: [a], message: "last wins")

  assert manifold.receive(channel, 100) == Ok("last wins")
}

pub fn overriding_options_keeps_the_same_receivers_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Binary)
  let parent = process.self()

  let a = spawn_echo(channel, parent)
  let b = spawn_echo(channel, parent)

  // A copy with different options still reaches everyone receiving from the
  // original, because the two share a reference.
  let unpacked = channel |> manifold.pack(manifold.Etf)
  manifold.broadcast(unpacked, to: [a, b], message: "still arrives")

  assert manifold.receive(channel, 100) == Ok("still arrives")
  assert manifold.receive(channel, 100) == Ok("still arrives")
}

// Selectors -------------------------------------------------------------------

pub fn selector_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  process.spawn(fn() {
    manifold.send(channel, to: parent, message: "via selector")
  })

  let selector = manifold.selector(channel)

  assert process.selector_receive(selector, 100) == Ok("via selector")
}

pub fn selector_ignores_other_channels_test() {
  let a = manifold.new_channel()
  let b = manifold.new_channel()
  let parent = process.self()

  manifold.send(b, to: parent, message: "for b")

  let selector = manifold.selector(a)

  assert process.selector_receive(selector, 5) == Error(Nil)
  assert manifold.receive(b, 5) == Ok("for b")
}

type Message {
  Broadcast(String)
  Command(Int)
}

pub fn select_alongside_a_process_subject_test() {
  let channel = manifold.new_channel()
  let commands = process.new_subject()
  let parent = process.self()

  let selector =
    process.new_selector()
    |> process.select_map(commands, Command)
    |> manifold.select_map(channel, Broadcast)

  process.send(commands, 42)
  manifold.send(channel, to: parent, message: "hello")

  assert process.selector_receive(selector, 100) == Ok(Command(42))
  assert process.selector_receive(selector, 100) == Ok(Broadcast("hello"))
  assert process.selector_receive(selector, 5) == Error(Nil)
}

pub fn select_broadcast_alongside_a_process_subject_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  let a = spawn_echo(channel, parent)
  let b = spawn_echo(channel, parent)

  let selector =
    process.new_selector()
    |> manifold.select_map(channel, Broadcast)

  manifold.broadcast(channel, to: [a, b], message: "fan out")

  assert process.selector_receive(selector, 100) == Ok(Broadcast("fan out"))
  assert process.selector_receive(selector, 100) == Ok(Broadcast("fan out"))
  assert process.selector_receive(selector, 5) == Error(Nil)
}

pub fn selecting_a_packed_broadcast_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Binary)
  let parent = process.self()

  let a = spawn_echo(channel, parent)
  let b = spawn_echo(channel, parent)

  let selector = manifold.selector(channel)

  manifold.broadcast(channel, to: [a, b], message: "packed and selected")

  assert process.selector_receive(selector, 100) == Ok("packed and selected")
  assert process.selector_receive(selector, 100) == Ok("packed and selected")
}

// Routing ---------------------------------------------------------------------

pub fn partitioner_key_test() {
  manifold.set_partitioner_key("test_key")

  let channel = manifold.new_channel()
  let parent = process.self()

  process.spawn(fn() {
    manifold.send(channel, to: parent, message: "After partitioner key")
  })

  assert manifold.receive(channel, 100) == Ok("After partitioner key")
}

pub fn sender_key_test() {
  manifold.set_sender_key("test_sender_key")

  let channel = manifold.new_channel()
  let parent = process.self()

  process.spawn(fn() {
    manifold.send(channel, to: parent, message: "After sender key")
  })

  assert manifold.receive(channel, 100) == Ok("After sender key")
}
