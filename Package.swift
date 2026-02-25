// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PotatoAB",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "PotatoAB", targets: ["PotatoAB"])
    ],
    dependencies: [
        .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.24.0"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "2.30.0")
    ],
    targets: [
        .executableTarget(
            name: "PotatoAB",
            dependencies: [
                .product(name: "MLX", package: "mlx-swift"),
                .product(name: "MLXRandom", package: "mlx-swift"),
                .product(name: "MLXNN", package: "mlx-swift"),
                .product(name: "MLXOptimizers", package: "mlx-swift"),
                .product(name: "MLXFFT", package: "mlx-swift"),
                .product(name: "MLXLLM", package: "mlx-swift-lm")
            ]
        )
    ]
)
