import gleam/erlang/process
import gleam/int
import gleam/list
import gleam/otp/actor
import gleam_manifold as manifold
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

// Helpers ---------------------------------------------------------------------

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

/// A message that is not a String, holding several kinds of term, so that
/// binary packing has something non trivial to round trip.
type Event {
  Event(id: Int, name: String, tags: List(String), payload: BitArray)
  Tick
}

fn spawn_event_echo(
  channel: manifold.Channel(Event),
  parent: process.Pid,
) -> process.Pid {
  process.spawn(fn() {
    let assert Ok(event) = manifold.receive(channel, 100)
    manifold.send(channel, to: parent, message: event)
  })
}

// Sending ---------------------------------------------------------------------

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

pub fn messages_from_one_sender_arrive_in_order_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  let numbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

  numbers
  |> list.each(fn(n) {
    manifold.send(channel, to: parent, message: int.to_string(n))
  })

  let received = numbers |> list.map(fn(_) { manifold.receive(channel, 500) })

  assert received == numbers |> list.map(fn(n) { Ok(int.to_string(n)) })
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

// Message types ---------------------------------------------------------------

pub fn packs_and_unpacks_a_custom_type_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Binary)
  let parent = process.self()

  let a = spawn_event_echo(channel, parent)
  let b = spawn_event_echo(channel, parent)

  let event =
    Event(id: 7, name: "created", tags: ["a", "b"], payload: <<1, 2, 3>>)

  manifold.broadcast(channel, to: [a, b], message: event)

  assert manifold.receive(channel, 100) == Ok(event)
  assert manifold.receive(channel, 100) == Ok(event)
}

pub fn packs_a_constructor_with_no_fields_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Binary)
  let parent = process.self()

  let a = spawn_event_echo(channel, parent)
  let b = spawn_event_echo(channel, parent)

  manifold.broadcast(channel, to: [a, b], message: Tick)

  assert manifold.receive(channel, 100) == Ok(Tick)
  assert manifold.receive(channel, 100) == Ok(Tick)
}

// Selectors -------------------------------------------------------------------

type Selected {
  Broadcast(String)
  Command(Int)
}

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

// Actors ----------------------------------------------------------------------

type ActorMessage {
  Delivered(String)
  Report(process.Subject(List(String)))
}

/// An actor that handles its own messages and Manifold broadcasts alike.
fn start_actor(
  channel: manifold.Channel(String),
) -> Result(actor.Started(process.Subject(ActorMessage)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    // A custom selector replaces the default one, so the actor's own subject
    // has to be added to it as well as the channel.
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> manifold.select_map(channel, Delivered)

    actor.initialised([])
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(fn(received, message) {
    case message {
      Delivered(text) -> actor.continue([text, ..received])
      Report(reply) -> {
        process.send(reply, received)
        actor.continue(received)
      }
    }
  })
  |> actor.start
}

pub fn actor_receives_broadcasts_test() {
  let channel = manifold.new_channel()

  let assert Ok(a) = start_actor(channel)
  let assert Ok(b) = start_actor(channel)

  manifold.broadcast(channel, to: [a.pid, b.pid], message: "to everyone")

  // Manifold hands off to a partitioner process, so delivery is asynchronous.
  process.sleep(50)

  assert process.call(a.data, 100, Report) == ["to everyone"]
  assert process.call(b.data, 100, Report) == ["to everyone"]
}

pub fn actor_handles_its_own_messages_too_test() {
  let channel = manifold.new_channel()
  let assert Ok(started) = start_actor(channel)

  // A normal message, sent over the actor's own subject.
  process.send(started.data, Delivered("direct"))
  // And a Manifold broadcast, over the channel.
  manifold.broadcast(channel, to: [started.pid], message: "broadcast")

  process.sleep(50)

  assert process.call(started.data, 100, Report) == ["broadcast", "direct"]
}

// Edge cases ------------------------------------------------------------------

/// Manifold delegates a one element list to its single pid path, which skips
/// packing entirely. The message still has to arrive.
pub fn broadcast_to_one_pid_skips_packing_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Binary)
  let parent = process.self()

  let a = spawn_event_echo(channel, parent)

  manifold.broadcast(channel, to: [a], message: Tick)

  assert manifold.receive(channel, 100) == Ok(Tick)
}

pub fn broadcast_to_no_pids_test() {
  let channel = manifold.new_channel()

  manifold.broadcast(channel, to: [], message: "into the void")

  assert manifold.receive(channel, 20) == Error(Nil)
}

pub fn broadcast_to_a_dead_pid_test() {
  let channel = manifold.new_channel()
  let parent = process.self()

  let dead = process.spawn(fn() { Nil })
  process.sleep(20)
  assert process.is_alive(dead) == False

  let alive = spawn_echo(channel, parent)

  // A stale pid in the list must not stop the live ones receiving.
  manifold.broadcast(channel, to: [dead, alive], message: "still delivered")

  assert manifold.receive(channel, 100) == Ok("still delivered")
}

pub fn broadcast_to_many_processes_test() {
  let channel = manifold.new_channel() |> manifold.pack(manifold.Binary)
  let parent = process.self()

  let pids =
    list.repeat(Nil, 25) |> list.map(fn(_) { spawn_echo(channel, parent) })

  manifold.broadcast(channel, to: pids, message: "fan out wide")

  let received =
    list.repeat(Nil, 25) |> list.map(fn(_) { manifold.receive(channel, 500) })

  assert list.length(received) == 25
  assert list.all(received, fn(r) { r == Ok("fan out wide") })
  assert manifold.receive(channel, 20) == Error(Nil)
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
