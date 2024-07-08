import Foundation

fileprivate protocol Awaitable: Sendable {
	func waitForCompletion() async
}

extension Task: Awaitable {
	func waitForCompletion() async {
		_ = try? await value
	}
}

public final class AsyncQueue: @unchecked Sendable {
#if compiler(>=6.0)
	public typealias ThrowingOperation<Success> = @isolated(any) @Sendable () async throws -> sending Success
	public typealias Operation<Success> = @isolated(any) @Sendable () async -> sending Success
#else
	public typealias ThrowingOperation<Success: Sendable> = @Sendable () async throws -> Success
	public typealias Operation<Success: Sendable> = @Sendable () async -> Success
#endif

	public typealias ErrorSequence = AsyncStream<Error>

	public struct Attributes: OptionSet, Sendable {
		public let rawValue: UInt64

		public static let concurrent = Attributes(rawValue: 1 << 0)
		public static let publishErrors = Attributes(rawValue: 2 << 0)

		public init(rawValue: UInt64) {
			self.rawValue = rawValue
		}
	}

	private struct QueueEntry {
		let awaitable: any Awaitable
		let isBarrier: Bool
		let id: UUID
	}

	private struct ExecutionProperties {
		let dependencies: [any Awaitable]
		let isBarrier: Bool
		let id: UUID
	}

	private let lock = NSLock()
	private var pendingTasks = [QueueEntry]()
	private let attributes: Attributes
	private let errorContinuation: ErrorSequence.Continuation

	/// An AsyncSequence of all errors thrown from operations.
	///
	/// Errors are published here even if a reference to the operation task is held and awaited. But, it can still very useful for logging and debugging purposes. This sequence will not include any `CancellationError`s thrown.
	public let errorSequence: ErrorSequence

	public init(attributes: Attributes = []) {
		self.attributes = attributes
		self.lock.name = "AsyncQueue"

		(self.errorSequence, self.errorContinuation) = ErrorSequence.makeStream()
	}

	private func completePendingTask(with props: ExecutionProperties) {
		lock.lock()
		defer { lock.unlock() }

		guard let idx = pendingTasks.firstIndex(where: { $0.id == props.id }) else {
			preconditionFailure("Pending task id not found for \(props)")
		}

		pendingTasks.remove(at: idx)
	}

	private func createTask<Success, Failure>(
		barrier: Bool,
		_ block: (ExecutionProperties) -> Task<Success, Failure>
	) -> Task<Success, Failure> {
		let id = UUID()

		lock.lock()
		defer { lock.unlock() }

		let dependencies: [any Awaitable]

		switch (barrier, attributes.contains(.concurrent)) {
		case (_, false):
			// this is the simple case of a plain ol' serial queue. Everything is a barrier.
			dependencies = pendingTasks.last.flatMap { [$0.awaitable] } ?? []
		case (false, true):
			// we must wait on the most-recently enqueued barrier
			let lastBarrier = pendingTasks.last(where: { $0.isBarrier })

			dependencies = lastBarrier.flatMap({ [$0.awaitable] }) ?? []
		case (true, true):
			// the trickiest case: wait for *all* tasks until the last barrier

			let idx = pendingTasks.lastIndex(where: { $0.isBarrier }) ?? pendingTasks.startIndex

			dependencies = pendingTasks.suffix(from: idx).map({ $0.awaitable })
		}

		let props = ExecutionProperties(dependencies: dependencies, isBarrier: barrier, id: id)
		let task = block(props)

		let entry = QueueEntry(awaitable: task, isBarrier: barrier, id: id)

		pendingTasks.append(entry)

		return task
	}

	private func executeOperation<Success>(
		props: ExecutionProperties,
		@_inheritActorContext operation: @escaping ThrowingOperation<Success>
	) async rethrows -> Success {
		for awaitable in props.dependencies {
			await awaitable.waitForCompletion()
		}

		defer {
			completePendingTask(with: props)
		}

		do {
			return try await operation()
		} catch is CancellationError {
			throw CancellationError()
		} catch {
#if compiler(>=5.9)
			if attributes.contains(.publishErrors) {
				errorContinuation.yield(error)
			}
#endif

			throw error
		}
	}
}

extension AsyncQueue {
	/// Submit a throwing operation to the queue.
	@discardableResult
	public func addOperation<Success>(
		priority: TaskPriority? = nil,
		barrier: Bool = false,
		@_inheritActorContext operation: @escaping ThrowingOperation<Success>
	) -> Task<Success, Error> {
		let asBarrier = barrier || attributes.contains([.concurrent]) == false

		return createTask(barrier: asBarrier) { props in
			Task<Success, Error>(priority: priority) {
				try await executeOperation(props: props, operation: operation)
			}
		}
	}

	/// Submit an operation to the queue.
	@discardableResult
	public func addOperation<Success>(
		priority: TaskPriority? = nil,
		barrier: Bool = false,
		@_inheritActorContext operation: @escaping Operation<Success>
	) -> Task<Success, Never> {
		let asBarrier = barrier || attributes.contains([.concurrent]) == false

		return createTask(barrier: asBarrier) { props in
			Task<Success, Never>(priority: priority) {
				await executeOperation(props: props, operation: operation)
			}
		}
	}
}

extension AsyncQueue {
	/// Submit a throwing barrier operation to the queue.
	@discardableResult
	public func addBarrierOperation<Success>(
		priority: TaskPriority? = nil,
		@_inheritActorContext operation: @escaping ThrowingOperation<Success>
	) -> Task<Success, Error> where Success : Sendable {
		return addOperation(priority: priority, barrier: true, operation: operation)
	}

	/// Submit a barrier operation to the queue.
	@discardableResult
	public func addBarrierOperation<Success>(
		priority: TaskPriority? = nil,
		@_inheritActorContext operation: @escaping Operation<Success>
	) -> Task<Success, Never> where Success : Sendable {
		return addOperation(priority: priority, barrier: true, operation: operation)
	}
}
