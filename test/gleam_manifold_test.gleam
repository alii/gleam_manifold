import gleam/erlang/process
import gleam_manifold as manifold
import gleeunit

pub fn main() -> Nil {
  gleeunit.main()
}

pub fn simple_test() {
  let tag = manifold.new_tag()
  let pid = process.self()
  process.spawn(fn() { manifold.send(pid, tag, "Hello world") })
  assert manifold.receive(tag, 100) == Ok("Hello world")
}

pub fn many_pids_test() {
  let tag = manifold.new_tag()
  let pid = process.self()

  let proc = fn() {
    let selector = process.new_selector() |> process.select_other(identity)
    let assert Ok(#(_ref, result)) = process.selector_receive(selector, 5)
    manifold.send(pid, tag, result)
  }

  let a = process.spawn(proc)
  let b = process.spawn(proc)

  manifold.send(a, tag, "hello from a")
  manifold.send(b, tag, "hello from b")

  assert manifold.receive(tag, 5) == Ok("hello from a")
  assert manifold.receive(tag, 5) == Ok("hello from b")
  assert manifold.receive(tag, 5) == Error(Nil)
}

pub fn multi_pids_test() {
  let tag = manifold.new_tag()
  let pid = process.self()

  let proc = fn() {
    let selector = process.new_selector() |> process.select_other(identity)
    let assert Ok(#(_ref, result)) = process.selector_receive(selector, 5)
    manifold.send(pid, tag, result)
  }

  let a = process.spawn(proc)
  let b = process.spawn(proc)

  manifold.send_multi([a, b], tag, "hello from both")

  assert manifold.receive(tag, 5) == Ok("hello from both")
  assert manifold.receive(tag, 5) == Ok("hello from both")
  assert manifold.receive(tag, 5) == Error(Nil)
}

pub fn send_with_options_test() {
  let tag = manifold.new_tag()
  let pid = process.self()

  process.spawn(fn() {
    manifold.send_with_options(pid, tag, "Test with binary packing", [
      manifold.PackModeOption(manifold.Binary),
    ])
  })
  assert manifold.receive(tag, 100) == Ok("Test with binary packing")

  process.spawn(fn() {
    manifold.send_with_options(pid, tag, "Test with ETF", [
      manifold.PackModeOption(manifold.Etf),
    ])
  })
  assert manifold.receive(tag, 100) == Ok("Test with ETF")

  process.spawn(fn() {
    manifold.send_with_options(pid, tag, "Test with offload", [
      manifold.SendModeOption(manifold.Offload),
    ])
  })
  assert manifold.receive(tag, 100) == Ok("Test with offload")

  process.spawn(fn() {
    manifold.send_with_options(pid, tag, "Test with multiple options", [
      manifold.PackModeOption(manifold.Binary),
      manifold.SendModeOption(manifold.Offload),
    ])
  })
  assert manifold.receive(tag, 100) == Ok("Test with multiple options")
}

pub fn send_multi_with_options_test() {
  let tag = manifold.new_tag()
  let pid = process.self()

  let proc = fn() {
    let selector = process.new_selector() |> process.select_other(identity)
    let assert Ok(#(_ref, result)) = process.selector_receive(selector, 5)
    manifold.send(pid, tag, result)
  }

  let a = process.spawn(proc)
  let b = process.spawn(proc)

  manifold.send_multi_with_options([a, b], tag, "multi with options", [
    manifold.PackModeOption(manifold.Binary),
  ])

  assert manifold.receive(tag, 100) == Ok("multi with options")
  assert manifold.receive(tag, 100) == Ok("multi with options")
  assert manifold.receive(tag, 5) == Error(Nil)
}

pub fn partitioner_key_test() {
  manifold.set_partitioner_key("test_key")

  let tag = manifold.new_tag()
  let pid = process.self()

  process.spawn(fn() { manifold.send(pid, tag, "After partitioner key") })
  assert manifold.receive(tag, 100) == Ok("After partitioner key")
}

pub fn sender_key_test() {
  manifold.set_sender_key("test_sender_key")

  let tag = manifold.new_tag()
  let pid = process.self()

  process.spawn(fn() { manifold.send(pid, tag, "After sender key") })
  assert manifold.receive(tag, 100) == Ok("After sender key")
}

@external(erlang, "gleam_erlang_ffi", "identity")
fn identity(x: a) -> b
