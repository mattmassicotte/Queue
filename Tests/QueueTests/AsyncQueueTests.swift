import XCTest
import Queue

enum QueueTestError: Error, Hashable {
	case operatorFailure
}

actor Counter {
	var count: Int = 0
	func increment() -> Int {
		count += 1
		return count
	}
}

func delay(milliseconds: UInt64) async throws  {
	try await Task.sleep(nanoseconds: milliseconds * 1_000_000)
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
			try await delay(milliseconds: 100)

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
			try await delay(milliseconds: 100)

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
			try await delay(milliseconds: 100)

			expA.fulfill()
		}

		queue.addOperation {
			try await delay(milliseconds: 100)

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
				try await delay(milliseconds: 100)
				expB.fulfill()
			}

			try await delay(milliseconds: 100)

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
				try await delay(milliseconds: 100)
				expB.fulfill()
			}

			queue.addOperation {
				expC.fulfill()
			}

			try await delay(milliseconds: 100)

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
			try await delay(milliseconds: 100)

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
			try await delay(milliseconds: 100)

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
			try await delay(milliseconds: 100)

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

	func testEnqueuePerformance() {
		let queue = AsyncQueue()

		measure {
			// techincally measuring the actor creation time too, but I don't think that is a big deal
			let s = Counter()

			for i in 1 ... 1_000 {
				queue.addOperation { [i] in
					let result = await s.increment()
					if i != result {
						print(i, "does not match", result)
					}
				}
			}
		}
	}

	func testPriorityInversionAvoidance() async throws {
		let queue = AsyncQueue(attributes: [.concurrent])

		let exp = expectation(description: "low priority task executed")

		queue.addOperation(priority: .low) {
			try await delay(milliseconds: 100)

			XCTAssertTrue(Task.currentPriority >= .high)
			exp.fulfill()
		}

		let task = queue.addOperation(priority: .high, barrier: true) {
			XCTAssertTrue(Task.currentPriority >= .high)
		}

		await task.value
		await fulfillment(of: [exp], timeout: 1.0)
	}

	func testLowPriority() async throws {
		let queue = AsyncQueue(attributes: [.concurrent])

		let exp = expectation(description: "low priority task executed")

		queue.addOperation(priority: .low) {
			XCTAssertTrue(Task.currentPriority == .low)

			exp.fulfill()
		}

		await fulfillment(of: [exp], timeout: 1.0)
	}

	func testCancelPendingTasks() async throws {
		let queue = AsyncQueue()
		let expQuick = expectation(description: "Quick task finished")
		let expCancelled = expectation(description: "Long task cancelled")
		
		// A task that completes quickly.
		let taskQuick = queue.addOperation {
			expQuick.fulfill()
			return "quick"
		}
		
		// A long-running task that should be cancelled.
		let taskLong = queue.addOperation {
			try await delay(milliseconds: 5_000)
			return "long"
		}
		
		await fulfillment(of: [expQuick], timeout: 1.0)
		
		// Cancel all pending tasks in the queue.
		queue.cancelAllPendingTasks()

		let quickResult = await taskQuick.value
		XCTAssertEqual(quickResult, "quick")
		
		do {
			_ = try await taskLong.value
			XCTFail("Expected CancellationError, but taskLong completed successfully")
		} catch is CancellationError {
			expCancelled.fulfill()
		}
		
		await fulfillment(of: [expCancelled], timeout: 1.0)
	}
	
	func testCancelDoesNotAffectNewOperations() async throws {
		let queue = AsyncQueue(attributes: [.concurrent])
		let expCancelled = expectation(description: "Cancelled task threw CancellationError")
		let expNew = expectation(description: "New task executed normally")
		
		// Schedule a long-running task that will be cancelled.
		let taskCancelled = queue.addOperation {
			try await delay(milliseconds: 5_000)
			return "cancelled"
		}
		
		// Cancel pending tasks.
		queue.cancelAllPendingTasks()

		do {
			_ = try await taskCancelled.value
			XCTFail("Expected CancellationError for taskCancelled")
		} catch is CancellationError {
			expCancelled.fulfill()
		}
		
		// Schedule a new task after cancellation; it should run normally.
		let taskNew = queue.addOperation {
			expNew.fulfill()
			return "new"
		}
		
		let newResult = await taskNew.value
		XCTAssertEqual(newResult, "new")
		
		await fulfillment(of: [expCancelled, expNew], timeout: 1.0)
	}
}
