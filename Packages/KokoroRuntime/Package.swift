// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KokoroRuntime",
    platforms: [.iOS(.v17)],
    products: [.library(name: "KokoroRuntime", targets: ["KokoroRuntime"])],
    targets: [
        .binaryTarget(name: "SherpaBinary", path: "Frameworks/sherpa-onnx.xcframework"),
        .binaryTarget(name: "OnnxBinary", path: "Frameworks/onnxruntime.xcframework"),
        .target(name: "KokoroRuntime", dependencies: ["SherpaBinary", "OnnxBinary"],
                linkerSettings: [.linkedLibrary("c++"), .linkedFramework("Accelerate"), .linkedFramework("CoreML")])
    ]
)
