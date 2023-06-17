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
	public struct Attributes: OptionSet, Sendable {
		public let rawValue: UInt64

		public static let concurrent = Attributes(rawValue: 1 << 0)

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

	public init(attributes: Attributes = []) {
		self.attributes = attributes
		self.lock.name = "AsyncQueue"
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

		return try await operation()
	}
}

extension AsyncQueue {
	/// Submit a throwing operation to the queue.
	@discardableResult
	public func addOperation<Success>(
		priority: TaskPriority? = nil,
		@_inheritActorContext operation: @escaping @Sendable () async throws -> Success
	) -> Task<Success, Error> where Success : Sendable {
		let serial = attributes.contains([.concurrent]) == false

		return createTask(barrier: serial) { props in
			Task<Success, Error>(priority: priority) { [unowned self] in
				try await self.executeOperation(props: props, operation: operation)
			}
		}
	}

	/// Submit an operation to the queue.
	@discardableResult
	public func addOperation<Success>(
		priority: TaskPriority? = nil,
		@_inheritActorContext operation: @escaping @Sendable () async -> Success
	) -> Task<Success, Never> where Success : Sendable {
		let serial = attributes.contains([.concurrent]) == false

		return createTask(barrier: serial) { props in
			Task<Success, Never>(priority: priority) { [unowned self] in
				await self.executeOperation(props: props, operation: operation)
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
		return createTask(barrier: true) { props in
			Task<Success, Error>(priority: priority) { [unowned self] in
				try await executeOperation(props: props, operation: operation)
			}
		}
	}

	/// Submit a barrier operation to the queue.
	@discardableResult
	public func addBarrierOperation<Success>(
		priority: TaskPriority? = nil,
		@_inheritActorContext operation: @escaping @Sendable () async -> Success)
	-> Task<Success, Never> where Success : Sendable {
		return createTask(barrier: true) { props in
			Task<Success, Never>(priority: priority) { [unowned self] in
				await executeOperation(props: props, operation: operation)
			}
		}
	}
}
