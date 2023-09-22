// see https://github.com/apple/swift-corelibs-xctest/issues/436

import Foundation

#if os(Linux)
import XCTest

extension XCTestCase {
	/// Wait on an array of expectations for up to the specified timeout, and optionally specify whether they
	/// must be fulfilled in the given order. May return early based on fulfillment of the waited on expectations.
	///
	/// - Parameter expectations: The expectations to wait on.
	/// - Parameter timeout: The maximum total time duration to wait on all expectations.
	/// - Parameter enforceOrder: Specifies whether the expectations must be fulfilled in the order
	///   they are specified in the `expectations` Array. Default is false.
	/// - Parameter file: The file name to use in the error message if
	///   expectations are not fulfilled before the given timeout. Default is the file
	///   containing the call to this method. It is rare to provide this
	///   parameter when calling this method.
	/// - Parameter line: The line number to use in the error message if the
	///   expectations are not fulfilled before the given timeout. Default is the line
	///   number of the call to this method in the calling file. It is rare to
	///   provide this parameter when calling this method.
	///
	/// - SeeAlso: XCTWaiter
	func fulfillment(of expectations: [XCTestExpectation], timeout: TimeInterval, enforceOrder: Bool = false) async {
		return await withCheckedContinuation { continuation in
			// This function operates by blocking a background thread instead of one owned by libdispatch or by the
			// Swift runtime (as used by Swift concurrency.) To ensure we use a thread owned by neither subsystem, use
			// Foundation's Thread.detachNewThread(_:).
			Thread.detachNewThread { [self] in
				wait(for: expectations, timeout: timeout, enforceOrder: enforceOrder)
				continuation.resume()
			}
		}
	}
}
#endif
