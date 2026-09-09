// ==========================================
// File: SimulatorGenerationArtifact.swift
// Spec: ADR-023 simulator engineering supplement; US-SYN-004
// Task: 4.0k - CPU-compatible simulator artifact
// AC coverage: separate identity, closed inventory and unchanged weights
// Scope: Debug simulator only; no device or release qualification
// ==========================================

import Foundation

#if DEBUG && targetEnvironment(simulator)
nonisolated enum SimulatorGenerationArtifact {
    static let prefillBatchSize = 4
    static let identity = "6a67bb65383697558556a14f2e1a7d12c2f79ad9e688f55bbe27466f75cdefff"
    static let modelName = "Qwen06BSimulatorPrefill4"
    static let computeBackend = "simulator-cpu-fixed-prefill4-rms-fp32-v3"
    static let resourceName = "OfflineGenerationSimulator"
    static var manifest: ModelManifest {
        ModelManifest(
            modelId: "qwen3-0.6b-simulator-prefill4-v2",
            revision: "c1899de289a04d12100db370d81485cdf75e47ca",
            artifactHash: identity,
            licenseId: "apache-2.0",
            runtime: .coreML,
            tokenizer: "qwen3-byte-bpe-pinned-v1",
            promptTemplate: GenerationPrompt.version,
            pooling: .none,
            normalization: .none,
            dimension: 151_936,
            quantization: "int8-per-channel-fp16-kv-fp32-rms"
        )
    }
    static let files: [GenerationArtifactFile] = [
        .init(
            path: "NOTICE.md",
            sizeBytes: 2457,
            sha256: "df324ae48313ca3679d02fbaa8bae4ff9e090ef29f645ddbc39b8c8975d900df"
        ),
        .init(
            path: "Qwen06BSimulatorPrefill4.mlmodelc/analytics/coremldata.bin",
            sizeBytes: 243,
            sha256: "fe0acd595d883c71f86cf3266f66658e1710cad535f5dbd82f33b9f7278e1457"
        ),
        .init(
            path: "Qwen06BSimulatorPrefill4.mlmodelc/coremldata.bin",
            sizeBytes: 2300,
            sha256: "3bfdf8a8485f40ffc68520f841d6820786114df9a819fd57f64cd7791def628c"
        ),
        .init(
            path: "Qwen06BSimulatorPrefill4.mlmodelc/metadata.json",
            sizeBytes: 18204,
            sha256: "d5621443bb305c1720e5827f8d57a43d5f71cde5e79022a372ae11f39fb27396"
        ),
        .init(
            path: "Qwen06BSimulatorPrefill4.mlmodelc/model.mil",
            sizeBytes: 761129,
            sha256: "31d6896ea9d56ae149bfb888eb85c0ae26b249a1e8a3b580ec4161f15c1fd6c3"
        ),
        .init(
            path: "Qwen06BSimulatorPrefill4.mlmodelc/weights/weight.bin",
            sizeBytes: 597727040,
            sha256: "520ac694a62aba1ff8d221141d64c84986ba781c8439a8569229efbd2f281d53"
        ),
        .init(
            path: "Qwen3Tokenizer/LICENSE",
            sizeBytes: 11343,
            sha256: "832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e"
        ),
        .init(
            path: "Qwen3Tokenizer/config.json",
            sizeBytes: 726,
            sha256: "660db3b73d788119c04535e48cf9be5f55bc3100841a718637ae695b442f27dd"
        ),
        .init(
            path: "Qwen3Tokenizer/generation_config.json",
            sizeBytes: 239,
            sha256: "2325da0f15bb848e018c5ae071b7943332e9f871d6b60e2ed22ca97d4cb993d2"
        ),
        .init(
            path: "Qwen3Tokenizer/tokenizer.json",
            sizeBytes: 11422654,
            sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"
        ),
        .init(
            path: "Qwen3Tokenizer/tokenizer_config.json",
            sizeBytes: 9732,
            sha256: "d5d09f07b48c3086c508b30d1c9114bd1189145b74e982a265350c923acd8101"
        ),
    ]
}
#endif
