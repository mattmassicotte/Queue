import XCTest
@testable import Queue

enum AsyncSerialQueueError: Error {
	case problem
}

final class AsyncSerialQueueTests: XCTestCase {

	func testEnqueuePerformance() {
		let queue = AsyncSerialQueue()

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

	func testThrowingOperation() {
		let queue = AsyncSerialQueue()

		queue.addOperation {
			throw AsyncSerialQueueError.problem
		}
	}
}
