/// A esrial queue implemented on top of AsyncSequence.
///
/// This type is an experiment. I believe it works, but it currently has no tests and has been used very little.
actor AsyncSerialQueue {
#if compiler(>=6.0)
	public typealias Operation<Failure> = @isolated(any) @Sendable () async throws(Failure) -> Void
#else
	public typealias Operation<Failure> = @Sendable () async throws -> Void
	public typealias NonThrowingOperation = @Sendable () async -> Void
#endif

	public actor QueueTask {
		var cancelled = false
		let operation: Operation<any Error>

		init(operation: @escaping Operation<any Error>) {
			self.operation = operation
		}

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

	/// Submit a throwing operation to the queue.
	@discardableResult
	public nonisolated func addOperation(
		@_inheritActorContext operation: @escaping Operation<any Error>
	) -> QueueTask {
		let queueTask = QueueTask(operation: operation)

		continuation.yield(queueTask)

		return queueTask
	}

#if compiler(<6.0)
	/// Submit an operation to the queue.
	@discardableResult
	public nonisolated func addOperation(
		@_inheritActorContext operation: @escaping NonThrowingOperation
	) -> QueueTask {
		let queueTask = QueueTask(operation: operation)

		continuation.yield(queueTask)

		return queueTask
	}
#endif
}
