/// A serial queue implemented on top of AsyncSequence.
///
/// This type is an experiment. I believe it works, but it currently has no tests and has been used very little.
actor AsyncSerialQueue {
	public actor QueueTask {
		var cancelled = false
#if compiler(>=6.0)
		let operation: @isolated(any) () async throws -> Void

		init(operation: @escaping @isolated(any) () async throws -> Void) {
			self.operation = operation
		}
#else
		let operation: @Sendable () async throws -> Void

		init(operation: @escaping @Sendable () async throws -> Void) {
			self.operation = operation
		}
#endif

		public nonisolated func cancel() {
			Task { await internalCancel() }
		}

		private func internalCancel() {
			cancelled = true
		}

		func run() async throws {
			if cancelled {
				return
			}

			try await operation()
		}
	}

	typealias Stream = AsyncStream<QueueTask>

	private let continuation: Stream.Continuation

	public init() {
		let (stream, continuation) = Stream.makeStream()

		self.continuation = continuation

		Task {
			for await item in stream {
				try? await item.run()
			}
		}
	}

	deinit {
		continuation.finish()
	}

#if compiler(<6.0)
	/// Submit a throwing operation to the queue.
	@discardableResult
	public nonisolated func addOperation(
		@_inheritActorContext operation: @escaping @Sendable () async throws -> Void
	) -> QueueTask {
		let queueTask = QueueTask(operation: operation)

		continuation.yield(queueTask)

		return queueTask
	}

	/// Submit an operation to the queue.
	@discardableResult
	public nonisolated func addOperation(
		@_inheritActorContext operation: @escaping @Sendable () async -> Void
	) -> QueueTask {
		let queueTask = QueueTask(operation: operation)

		continuation.yield(queueTask)

		return queueTask
	}
#else
	/// Submit an operation to the queue.
	@discardableResult
	public nonisolated func addOperation<Failure>(
		@_inheritActorContext operation: sending @escaping @isolated(any) () async throws(Failure) -> Void
	) -> QueueTask {
		let queueTask = QueueTask(operation: operation)

		continuation.yield(queueTask)

		return queueTask
	}
#endif
}
