<div align="center">

[![Build Status][build status badge]][build status]
[![Platforms][platforms badge]][platforms]
[![Documentation][documentation badge]][documentation]

</div>

# Queue

> Originally created by @mattmassicotte. Now maintained by @dimasusername.

A queue for Swift concurrency

This package exposes a single type: `AsyncQueue`. Conceptually, `AsyncQueue` is very similar to a `DispatchQueue` or `OperationQueue`. However, unlike these an `AsyncQueue` can accept async blocks. This exists to more easily enforce ordering across unstructured tasks without requiring explicit dependencies between them.

I've found this helpful when interfacing stateful asynchronous systems with synchronous code.

If you are looking for help handling actor reentrancy, check out [TaskGate](https://github.com/dimasusername/TaskGate) and [Semaphore][semaphore].

## Integration

```swift
dependencies: [
    .package(url: "https://github.com/dimasusername/Queue", from: "0.2.2")
]
```

## Usage

```swift
let queue = AsyncQueue()

queue.addOperation {
    await asyncFunction()
    await anotherAsyncFunction()
}

// This can can also return the underlying Task,
// so you can cancel, or await a value
let task = queue.addOperation {
    return await makeValue()
}

let value = try await task.value
```

By default, `AsyncQueue` will only run one operation at a time. But, it can be configured as a concurrent queue.

```swift
let queue = AsyncQueue(attributes: [.concurrent])

// these two may run concurrently
queue.addOperation { await asyncFunction() }
queue.addOperation { await asyncFunction() }

// This will only run once existing operations are complete, and will
// prevent new operations from starting until done
queue.addBarrierOperation {
    await asyncFunction()
}
```

The `AsyncQueue` type has an `errorSequence` property, which can be used to detect uncaught errors out of band.

```swift
let queue = AsyncQueue(attributes: [.publishErrors])

Task {
    for await error in queue.errorSequence {
        print(error)
    }
}
```

This package was inspired by [Semaphore][semaphore], which is another concurrency-related synchronization system that I've found very useful.

## Alternatives

- [swift-async-queue](https://github.com/dfed/swift-async-queue)
- [AsyncQueues](https://github.com/groue/AsyncQueues)

## Contributing and Collaboration

I would love to hear from you! Issues or pull requests work great. I have a strong bias towards answering in the form of documentation.

I prefer collaboration, and would love to find ways to work together if you have a similar project.

I prefer indentation with tabs for improved accessibility. But, I'd rather you use the system you want and make a PR than hesitate because of whitespace.

By participating in this project you agree to abide by the [Contributor Code of Conduct](CODE_OF_CONDUCT.md).

[build status]: https://github.com/dimasusername/Queue/actions
[build status badge]: https://github.com/dimasusername/Queue/workflows/CI/badge.svg
[platforms]: https://swiftpackageindex.com/dimasusername/Queue
[platforms badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fdimasusername%2FQueue%2Fbadge%3Ftype%3Dplatforms
[documentation]: https://swiftpackageindex.com/dimasusername/Queue/main/documentation
[documentation badge]: https://img.shields.io/badge/Documentation-DocC-blue
[semaphore]: https://github.com/groue/Semaphore
