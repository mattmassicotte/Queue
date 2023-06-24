import XCTest
import Queue

extension Task where Success == Never, Failure == Never {
	static func sleep(milliseconds: UInt64) async throws {
		try await sleep(nanoseconds: milliseconds * NSEC_PER_MSEC)
	}
}

enum QueueTestError: Error, Hashable {
	case operatorFailure
}

final class AsyncQueueTests: XCTestCase {
	func testSerialOrder() async {
		let queue = AsyncQueue()

		var tasks = [Task<TimeInterval, Never>]()
		for _ in 0..<1_000 {
			let task = queue.addOperation { Date().timeIntervalSince1970 }
			tasks.append(task)
		}

		var array = [TimeInterval]()
		for t in tasks {
			array.append(await t.value)
		}

		XCTAssertEqual(array, array.sorted())
	}

	func testBarriersAreSerial() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		var tasks = [Task<TimeInterval, Never>]()
		for _ in 0..<1_000 {
			let task = queue.addBarrierOperation { Date().timeIntervalSince1970 }
			tasks.append(task)
		}

		var array = [TimeInterval]()
		for t in tasks {
			array.append(await t.value)
		}

		XCTAssertEqual(array, array.sorted())

	}
	
	func testThrowingTask() async {
		let queue = AsyncQueue()

		let taskA = queue.addOperation {
			throw CancellationError()
		}

		let taskB = queue.addOperation {
			return "B"
		}

		do {
			// this should throw
			let _ = try await taskA.value

			XCTFail()
		} catch {
		}

		let value = await taskB.value

		XCTAssertEqual(value, "B")
	}

	func testConcurrentTasksRunCanOutOfOrder() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		let expB = expectation(description: "Task B")

		queue.addOperation {
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		queue.addOperation {
			expB.fulfill()
		}

		await fulfillment(of: [expB, expA], enforceOrder: true)
	}

	func testTaskWaitsForPreceedingBarrier() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		queue.addBarrierOperation {
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		let expB = expectation(description: "Task B")
		queue.addOperation {
			expB.fulfill()
		}

		await fulfillment(of: [expA, expB], enforceOrder: true)
	}

	func testConcurrentTasksOnlyWaitForBarrier() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		let expB = expectation(description: "Task B")
		let expC = expectation(description: "Task C")

		queue.addBarrierOperation {
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		queue.addOperation {
			try await Task.sleep(milliseconds: 100)

			expB.fulfill()
		}

		queue.addOperation {
			expC.fulfill()
		}

		await fulfillment(of: [expA, expC, expB], enforceOrder: true)
	}

	func testAddBarrierWhileBarrierRunning() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		let expB = expectation(description: "Task B")
		let expC = expectation(description: "Task C")

		queue.addBarrierOperation {
			queue.addBarrierOperation {
				try await Task.sleep(milliseconds: 100)
				expB.fulfill()
			}

			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		queue.addOperation {
			expC.fulfill()
		}

		await fulfillment(of: [expA, expC, expB], enforceOrder: true)
	}

	func testAddBarrierWhileBarrierRunningBlocksSubsequenceTasks() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		let expB = expectation(description: "Task B")
		let expC = expectation(description: "Task C")

		queue.addBarrierOperation {
			queue.addBarrierOperation {
				try await Task.sleep(milliseconds: 100)
				expB.fulfill()
			}

			queue.addOperation {
				expC.fulfill()
			}

			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		await fulfillment(of: [expA, expB, expC], enforceOrder: true)
	}

	func testBarrierWaitsForAllTasksBeforeRunning() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		let expB = expectation(description: "Task B")

		queue.addOperation {
			// slow, non-barrier
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		queue.addBarrierOperation {
			expB.fulfill()
		}

		await fulfillment(of: [expA, expB], enforceOrder: true)
	}

	func testCancelOperation() async throws {
		let queue = AsyncQueue(attributes: [])

		let expA = expectation(description: "Task A")
		expA.isInverted = true

		let expB = expectation(description: "Task B")

		let task = queue.addOperation {
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		queue.addOperation {
			expB.fulfill()
		}

		task.cancel()

		await fulfillment(of: [expA, expB], timeout: 0.5, enforceOrder: true)
	}
}

extension AsyncQueueTests {
	func testPublishUncaughtErrors() async throws {
		let queue = AsyncQueue(attributes: [.publishErrors])

		var iterator = queue.errorSequence.makeAsyncIterator()

		queue.addOperation {
			throw QueueTestError.operatorFailure
		}

		let error = await iterator.next()

		XCTAssertEqual(error as? QueueTestError, QueueTestError.operatorFailure)
	}

	func testCancelErrorsNoPublished() async throws {
		let queue = AsyncQueue(attributes: [.publishErrors])

		var iterator = queue.errorSequence.makeAsyncIterator()

		let expA = expectation(description: "Cancelled Task")
		expA.isInverted = true

		let task = queue.addOperation {
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		task.cancel()

		// we cannot yet wait, because there should be no errors in here
		queue.addOperation {
			throw QueueTestError.operatorFailure
		}

		await fulfillment(of: [expA], timeout: 0.5, enforceOrder: true)

		let error = await iterator.next()

		XCTAssertEqual(error as? QueueTestError, QueueTestError.operatorFailure)

	}
}
