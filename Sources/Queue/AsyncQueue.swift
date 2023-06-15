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

	private struct ExecutionProperties {
		let dependencies: [any Awaitable]
		let isBarrier: Bool
		let id: UUID
	}

	private let semaphore = DispatchSemaphore(value: 1)
	private var pendingTasks = [UUID: any Awaitable]()
	private var barrierPending = false
	private let attributes: Attributes

	public init(attributes: Attributes = []) {
		self.attributes = attributes
	}

	private func completePendingTask(with props: ExecutionProperties) {
		semaphore.wait()
		defer { semaphore.signal() }

		precondition(pendingTasks[props.id] != nil)
		pendingTasks[props.id] = nil

		if props.isBarrier {
			self.barrierPending = false
		}
	}

	private func createTask<Success, Failure>(
		barrier: Bool,
		_ block: (ExecutionProperties) -> Task<Success, Failure>
	) -> Task<Success, Failure> {
		let id = UUID()

		semaphore.wait()
		defer { semaphore.signal() }

		let mustWait = barrier || barrierPending

		if barrier {
			self.barrierPending = true
		}

		precondition(pendingTasks[id] == nil)

		var values = [any Awaitable]()

		if mustWait {
			for (key, value) in pendingTasks {
				if key != id {
					values.append(value)
				}
			}
		}

		let props = ExecutionProperties(dependencies: values, isBarrier: barrier, id: id)
		let task = block(props)

		precondition(pendingTasks[id] == nil)
		pendingTasks[id] = task

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
