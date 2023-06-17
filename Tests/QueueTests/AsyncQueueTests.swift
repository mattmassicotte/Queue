import XCTest
import Queue

extension Task where Success == Never, Failure == Never {
	static func sleep(milliseconds: UInt64) async throws {
		try await sleep(nanoseconds: milliseconds * NSEC_PER_MSEC)
	}
}

final class QueueTests: XCTestCase {
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

	func testConcurrentQueue() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		queue.addOperation {
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		let expB = expectation(description: "Task B")
		queue.addOperation {
			expB.fulfill()
		}

		await fulfillment(of: [expB, expA], enforceOrder: true)
	}

	func testSingleBarrierOperation() async {
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
		queue.addBarrierOperation {
			try await Task.sleep(milliseconds: 100)

			expA.fulfill()
		}

		let expB = expectation(description: "Task B")
		queue.addOperation {
			try await Task.sleep(milliseconds: 100)

			expB.fulfill()
		}

		let expC = expectation(description: "Task C")
		queue.addOperation {
			expC.fulfill()
		}

		await fulfillment(of: [expA, expC, expB], enforceOrder: true)
	}

	func testBarrierThatAddsBarrierThenTask() async {
		let queue = AsyncQueue(attributes: [.concurrent])

		let expA = expectation(description: "Task A")
		let expB = expectation(description: "Task B")
		let expC = expectation(description: "Task C")

		queue.addBarrierOperation {
			queue.addBarrierOperation {
				try await Task.sleep(milliseconds: 100)
				expB.fulfill()
			}

			expA.fulfill()
		}

		queue.addOperation {
			expC.fulfill()
		}

		await fulfillment(of: [expA, expC, expB], enforceOrder: true)
	}

	func testBarrierThatAddsBarrierAndTask() async {
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

			expA.fulfill()
		}

		await fulfillment(of: [expA, expB, expC], enforceOrder: true)
	}
}
