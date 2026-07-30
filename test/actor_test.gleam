import gleam/erlang/process
import gleam/otp/actor
import gleam_manifold as manifold
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

type Message {
  Broadcast(String)
  Report(process.Subject(List(String)))
}

/// An actor that handles its own messages and Manifold broadcasts alike.
fn start(
  channel: manifold.Channel(String),
) -> Result(actor.Started(process.Subject(Message)), actor.StartError) {
  actor.new_with_initialiser(1000, fn(subject) {
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> manifold.select_map(channel, Broadcast)

    actor.initialised([])
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(fn(received, message) {
    case message {
      Broadcast(text) -> actor.continue([text, ..received])
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

  let assert Ok(a) = start(channel)
  let assert Ok(b) = start(channel)

  manifold.broadcast(channel, to: [a.pid, b.pid], message: "to everyone")

  // Manifold hands off to a partitioner process, so delivery is asynchronous.
  process.sleep(50)

  assert process.call(a.data, 100, Report) == ["to everyone"]
  assert process.call(b.data, 100, Report) == ["to everyone"]
}

pub fn actor_handles_its_own_messages_too_test() {
  let channel = manifold.new_channel()
  let assert Ok(started) = start(channel)

  // A normal message, sent over the actor's own subject.
  process.send(started.data, Broadcast("direct"))
  // And a Manifold broadcast, over the channel.
  manifold.broadcast(channel, to: [started.pid], message: "broadcast")

  process.sleep(50)

  assert process.call(started.data, 100, Report) == ["broadcast", "direct"]
}
