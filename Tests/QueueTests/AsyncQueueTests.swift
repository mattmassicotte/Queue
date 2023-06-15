import XCTest
import Queue

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

	func testBarrier() async {
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
}
