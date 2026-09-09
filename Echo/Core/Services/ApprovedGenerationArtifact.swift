// ==========================================
// File: ApprovedGenerationArtifact.swift
// Spec: ADR-009/023; US-SYN-004
// Task: 4.0k - Human-approved resource identity
// AC coverage: exact compiled weights, tokenizer, configuration and license
// Approval: 2026-09-08; artifact use and integration only
// Architecture: AGENTS.md R-005; no runtime download
// ==========================================

import Foundation

nonisolated enum ApprovedGenerationArtifact {
    static let prefillBatchSize = 1
    static let identity = "0e202c15169faf241d6ca77fa905493c7d3e57ba1e27f8df2d67c4fc58f136a7"
    static let resourceName = "OfflineGeneration"
    static let modelName = "Qwen06BContext1024Int8Channel"
    static var manifest: ModelManifest {
        ModelManifest(
            modelId: "qwen3-0.6b-generation-context1024-int8-v1",
            revision: "c1899de289a04d12100db370d81485cdf75e47ca",
            artifactHash: identity,
            licenseId: "apache-2.0",
            runtime: .coreML,
            tokenizer: "qwen3-byte-bpe-pinned-v1",
            promptTemplate: GenerationPrompt.version,
            pooling: .none,
            normalization: .none,
            dimension: 151_936,
            quantization: "int8-per-channel-fp16-compute-kv"
        )
    }
    #if targetEnvironment(simulator)
        static let computeBackend = "simulator-cpu-and-gpu"
    #else
        static let computeBackend = "device-cpu-and-gpu"
    #endif
    static let files: [GenerationArtifactFile] = [
        .init(
            path: "Qwen06BContext1024Int8Channel.mlmodelc/analytics/coremldata.bin",
            sizeBytes: 243,
            sha256: "b83f555ed7bf1946ec810e6e205c13470d624a9d27cd4997189f3d4ff3a9ad6f"
        ),
        .init(
            path: "Qwen06BContext1024Int8Channel.mlmodelc/coremldata.bin",
            sizeBytes: 2617,
            sha256: "ba8ebfaa7d8f18a4c592e05d8349d9110977490b2fb7b61fffb7cf62823acd83"
        ),
        .init(
            path: "Qwen06BContext1024Int8Channel.mlmodelc/metadata.json",
            sizeBytes: 18316,
            sha256: "45781319213c38c4aed983ab8d4992d6bc855491cee64023cf64234d339efc42"
        ),
        .init(
            path: "Qwen06BContext1024Int8Channel.mlmodelc/model.mil",
            sizeBytes: 726091,
            sha256: "22630672db541c9bece04187083d4598a6539bf21f389578ac098c8471e43988"
        ),
        .init(
            path: "Qwen06BContext1024Int8Channel.mlmodelc/weights/weight.bin",
            sizeBytes: 597_729_152,
            sha256: "24cb6248d93c55437655bdfe1c218528c7c593c0fdda9374322e03ae8ac7bfd8"
        ),
        .init(
            path: "Qwen3Tokenizer/tokenizer.json",
            sizeBytes: 11_422_654,
            sha256: "aeb13307a71acd8fe81861d94ad54ab689df773318809eed3cbe794b4492dae4"
        ),
        .init(
            path: "Qwen3Tokenizer/tokenizer_config.json",
            sizeBytes: 9732,
            sha256: "d5d09f07b48c3086c508b30d1c9114bd1189145b74e982a265350c923acd8101"
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
            path: "Qwen3Tokenizer/LICENSE",
            sizeBytes: 11343,
            sha256: "832dd9e00a68dd83b3c3fb9f5588dad7dcf337a0db50f7d9483f310cd292e92e"
        ),
        .init(
            path: "NOTICE.md",
            sizeBytes: 2457,
            sha256: "df324ae48313ca3679d02fbaa8bae4ff9e090ef29f645ddbc39b8c8975d900df"
        ),
    ]
}
