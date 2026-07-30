# gleam_manifold

Gleam bindings to [Manifold](https://github.com/discord/manifold), Discord's Elixir library for sending one message to many processes quickly. Instead of sending to each process in turn, Manifold dispatches to one partitioner per node and fans out from there.

## Install

```toml
[dependencies]
gleam_manifold = { git = "git@github.com:alii/gleam_manifold.git", ref = "<commit hash>" }
```

## Usage

A `Channel` is a typed address. Unlike a `process.Subject` it has no owner, so any number of processes can receive from it and `broadcast` reaches all of them in one call.

Create a channel once and share it with everything that uses it. Manifold delivers to pids, so keeping the list of processes you want to reach is up to you.

A channel goes into a `process.Selector`, so an actor can handle broadcasts alongside its own messages:

```gleam
import gleam/erlang/process
import gleam/io
import gleam/otp/actor
import gleam_manifold as manifold

type Message {
  Broadcast(String)
  Shutdown
}

fn start(channel: manifold.Channel(String)) {
  actor.new_with_initialiser(1000, fn(subject) {
    // A custom selector replaces the default one, so add the actor's own
    // subject to it as well as the channel.
    let selector =
      process.new_selector()
      |> process.select(subject)
      |> manifold.select_map(channel, Broadcast)

    actor.initialised(Nil)
    |> actor.selecting(selector)
    |> actor.returning(subject)
    |> Ok
  })
  |> actor.on_message(fn(state, message) {
    case message {
      Broadcast(text) -> {
        io.println(text)
        actor.continue(state)
      }
      Shutdown -> actor.stop()
    }
  })
  |> actor.start
}

pub fn main() {
  let channel = manifold.new_channel()

  let assert Ok(a) = start(channel)
  let assert Ok(b) = start(channel)

  // One call, both actors.
  manifold.broadcast(channel, to: [a.pid, b.pid], message: "hello")
}
```

Use `send` to reach one process and `broadcast` for many. Sends are asynchronous: Manifold hands the message to a partitioner process, so it arrives shortly after the call returns rather than during it.

For a process that is not an actor, `manifold.receive` and `manifold.receive_forever` read from a channel directly.

## Options

Options live on the channel.

```gleam
let channel =
  manifold.new_channel()
  |> manifold.pack(manifold.Binary)
  |> manifold.send_mode(manifold.Offload)
```

`Binary` serialises the message once with `term_to_binary` rather than once per receiving node, which pays off for large messages going to many nodes. `Etf` is the default and does no packing. Packing is ignored when sending to a single process.

`Offload` hands the message to a sender process so sending never blocks the caller. `Direct` is the default.

`pack` and `send_mode` return a copy sharing the channel's reference, so the same processes still receive it. That makes a one-off override safe:

```gleam
let unpacked = channel |> manifold.pack(manifold.Etf)
manifold.broadcast(unpacked, to: workers, message: "small")
```

## Selectors

`select_map` converts a channel's messages into your selector's type, as above. `select` adds a channel whose messages already are that type, and `manifold.selector(channel)` builds a selector for one channel on its own.

Build selectors outside your receive loop, as each call allocates. There is no `deselect`, since `gleam_erlang` has no record based equivalent; rebuild the selector without the channel instead.

## Routing

`set_partitioner_key` and `set_sender_key` pin the calling process to a partitioner or sender. Two processes sharing a key share a partitioner, so their messages to a given node stay ordered relative to one another. Both apply to every subsequent send from that process.

```gleam
manifold.set_partitioner_key("user_123")
```

## Migrating from 1.x

| 1.x                          | 2.x                                          |
| ---------------------------- | -------------------------------------------- |
| `new_tag()`                  | `new_channel()`                              |
| `send(pid, tag, msg)`        | `send(channel, to: pid, message: msg)`       |
| `send_multi(pids, tag, msg)` | `broadcast(channel, to: pids, message: msg)` |
| `send_with_options(...)`     | options go on the channel                    |
| `[PackModeOption(Binary)]`   | `channel \|> pack(Binary)`                   |
| `NoPacking`                  | `Etf`                                        |

`NoPacking` is gone because Manifold passes anything that is not `:binary` through unchanged, making it identical to `Etf`. `selector`, `select` and `select_map` are new.

## Why not `process.Subject`?

A subject has one owner and a tag unique to it, with no way to read that tag back out. Manifold needs many processes sharing a tag, and needs the tag itself to build the term it sends, so a subject can express neither half.

`gleam_erlang` has `unsafely_create_subject`, which would work, but it is internal and the contract for what a tag means lives there rather than here. It also hands back something with an owner, which a channel does not have, so `process.send` would compile against it and quietly turn a broadcast into a send to one process.

## Testing

```sh
gleam test
```
