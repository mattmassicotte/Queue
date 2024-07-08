// swift-tools-version: 5.9

import PackageDescription

let package = Package(
	name: "Queue",
	platforms: [
		.macOS(.v10_15),
		.macCatalyst(.v13),
		.iOS(.v13),
		.tvOS(.v13),
		.watchOS(.v6)
	],
	products: [
		.library(name: "Queue", targets: ["Queue"]),
	],
	targets: [
		.target(name: "Queue"),
		.testTarget(name: "QueueTests", dependencies: ["Queue"]),
	]
)

let swiftSettings: [SwiftSetting] = [
	.enableExperimentalFeature("StrictConcurrency"),
	.enableExperimentalFeature("IsolatedAny"),
]

for target in package.targets {
	var settings = target.swiftSettings ?? []
	settings.append(contentsOf: swiftSettings)
	target.swiftSettings = settings
}
