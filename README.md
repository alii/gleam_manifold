# gleam_manifold

Gleam bindings to [Manifold](https://github.com/discord/manifold) - an Elixir library for fast message passing between BEAM nodes.

## What is Manifold?

Manifold is an Elixir library developed by Discord that optimizes sending the same message to many processes. Instead of sending messages sequentially (which can be slow with thousands of processes), Manifold uses a divide-and-conquer approach that distributes the work across multiple sender processes, achieving much better performance at scale.

## Installation

Add to your `gleam.toml` as a git dependency:

```toml
[dependencies]
gleam_manifold = { git = "git@github.com:alii/gleam_manifold.git", ref = "<commit hash>" }
```

## Usage

### Creating and using Tags

This library provides its own Tag type for type-safe message passing:

```gleam
import gleam/erlang/process
import gleam_manifold as manifold

pub fn example() {
  let tag = manifold.new_tag()
  let pid = process.self()

  // Send a message through Manifold
  manifold.send(pid, tag, "Hello world")

  // Receive the message
  let assert Ok(message) = manifold.receive(subject, 1000)
}
```

### Multicasting to multiple PIDs

Send the same message to multiple processes at once:

```gleam
import gleam/erlang/process
import gleam_manifold as manifold

pub fn broadcast(pids: List(process.Pid), message: String) {
  let tag = manifold.new_tag()
  manifold.send_multi(pids, tag, message)
}
```

### Advanced Options

The library supports the same options as the Elixir Manifold library for tuning performance:

#### Pack Modes

Control how messages are serialized before sending:

```gleam
import gleam_manifold as manifold

pub fn send_with_packing() {
  let tag = manifold.new_tag()
  let pid = process.self()

  // Binary packing - efficient for large messages sent to many processes
  manifold.send_with_options(
    pid,
    subject,
    large_data,
    [manifold.PackModeOption(manifold.Binary)]
  )

  // ETF (Erlang Term Format) - default behavior
  manifold.send_with_options(
    pid,
    subject,
    data,
    [manifold.PackModeOption(manifold.Etf)]
  )

  // No packing
  manifold.send_with_options(
    pid,
    subject,
    data,
    [manifold.PackModeOption(manifold.NoPacking)]
  )
}
```

#### Send Modes

Control how messages are delivered:

```gleam
import gleam_manifold as manifold

pub fn send_with_offload() {
  let tag = manifold.new_tag()
  let pids = get_many_pids()

  // Offload mode - non-blocking, routes through sender processes
  manifold.send_multi_with_options(
    pids,
    subject,
    message,
    [manifold.SendModeOption(manifold.Offload)]
  )

  // Direct mode (default) - sends directly
  manifold.send_multi_with_options(
    pids,
    subject,
    message,
    [manifold.SendModeOption(manifold.Direct)]
  )
}
```

#### Combining Options

You can combine multiple options for fine-tuned control:

```gleam
pub fn optimized_broadcast(pids: List(process.Pid), message: String) {
  let tag = manifold.new_tag()

  // Use binary packing with offload mode for optimal performance
  manifold.send_multi_with_options(
    pids,
    subject,
    message,
    [
      manifold.PackModeOption(manifold.Binary),
      manifold.SendModeOption(manifold.Offload)
    ]
  )
}
```

### Partitioner and Sender Keys

Control load distribution across Manifold's internal processes:

```gleam
import gleam_manifold as manifold

pub fn with_custom_routing() {
  // Set a custom partitioner key for consistent routing
  manifold.set_partitioner_key("user_123")

  // Set a custom sender key for offloaded messages
  manifold.set_sender_key("channel_456")

  // Messages will be routed based on these keys
  manifold.send(pid, tag, message)
}
```

This is useful for:

- Ensuring message ordering for specific entities
- Load balancing across partitioner processes
- Preventing hot spots in message distribution

## Testing

Run the tests with:

```bash
gleam test
```

## License

See the LICENSE file in the repository.
