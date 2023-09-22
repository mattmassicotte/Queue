// swift-tools-version: 5.8

import PackageDescription

let settings: [SwiftSetting] = [
	.enableExperimentalFeature("StrictConcurrency")
]

let package = Package(
	name: "Queue",
	platforms: [.macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)],
	products: [
		.library(name: "Queue", targets: ["Queue"]),
	],
	targets: [
		.target(name: "Queue", swiftSettings: settings),
		.testTarget(name: "QueueTests", dependencies: ["Queue"], swiftSettings: settings),
	]
)
