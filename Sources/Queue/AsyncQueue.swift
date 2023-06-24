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
	private var pendingTasks = [UUID: QueueEntry]()
	private let attributes: Attributes
	private let errorContinuation: ErrorSequence.Continuation

	/// An AsyncSequence of all errors thrown from operations.
	///
	/// Errors are published here even if a reference to the operation task is held and awaited. But, it can still very useful for logging and debugging purposes. This sequence will not include any `CancellationError`s thrown.
	public let errorSequence: ErrorSequence

	public init(attributes: Attributes = []) {
		self.attributes = attributes
		self.lock.name = "AsyncQueue"

#if compiler(>=5.9)
		(self.errorSequence, self.errorContinuation) = ErrorSequence.makeStream()
#else
		var escapedContinuation: ErrorSequence.Continuation?

		self.errorSequence = ErrorSequence { escapedContinuation = $0 }

		self.errorContinuation = escapedContinuation!
#endif
	}

	private func completePendingTask(with props: ExecutionProperties) {
		lock.lock()
		defer { lock.unlock() }

		precondition(pendingTasks[props.id] != nil)
		pendingTasks[props.id] = nil
	}

	private var allPendingTasks: [any Awaitable] {
		pendingTasks.values.map({ $0.awaitable })
	}

	private var barriers: [any Awaitable] {
		pendingTasks.values.filter({ $0.isBarrier }).map({ $0.awaitable })
	}

	private func createTask<Success, Failure>(
		barrier: Bool,
		_ block: (ExecutionProperties) -> Task<Success, Failure>
	) -> Task<Success, Failure> {
		let id = UUID()

		lock.lock()
		defer { lock.unlock() }

		precondition(pendingTasks[id] == nil)

		// if we are a barrier, we have to wait for all existing tasks.
		// othewise, we really only need to wait for the latest barrier, but
		// since *that* has to wait for all tasks, this should be equivalent.
		let dependencies = barrier ? allPendingTasks : barriers

		let props = ExecutionProperties(dependencies: dependencies, isBarrier: barrier, id: id)
		let task = block(props)

		let entry = QueueEntry(awaitable: task, isBarrier: barrier, id: id)

		precondition(pendingTasks[id] == nil)
		pendingTasks[id] = entry

		return task
	}

	private func executeOperation<Success>(
		props: ExecutionProperties,
		@_inheritActorContext operation: @escaping @Sendable () async throws -> Success
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
		@_inheritActorContext operation: @escaping @Sendable () async throws -> Success
	) -> Task<Success, Error> where Success : Sendable {
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
		@_inheritActorContext operation: @escaping @Sendable () async -> Success
	) -> Task<Success, Never> where Success : Sendable {
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
		@_inheritActorContext operation: @escaping @Sendable () async throws -> Success)
	-> Task<Success, Error> where Success : Sendable {
		return addOperation(priority: priority, barrier: true, operation: operation)
	}

	/// Submit a barrier operation to the queue.
	@discardableResult
	public func addBarrierOperation<Success>(
		priority: TaskPriority? = nil,
		@_inheritActorContext operation: @escaping @Sendable () async -> Success)
	-> Task<Success, Never> where Success : Sendable {
		return addOperation(priority: priority, barrier: true, operation: operation)
	}
}
