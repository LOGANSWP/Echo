// ==========================================
// File: GenerationRuntimeArtifact.swift
// Spec: ADR-023 simulator engineering supplement; US-SYN-004
// Task: 4.0k - Build-scoped resource selection
// AC coverage: simulator derivatives cannot enter device or Release builds
// ==========================================

#if DEBUG && targetEnvironment(simulator)
typealias GenerationRuntimeArtifact = SimulatorGenerationArtifact
#else
typealias GenerationRuntimeArtifact = ApprovedGenerationArtifact
#endif
