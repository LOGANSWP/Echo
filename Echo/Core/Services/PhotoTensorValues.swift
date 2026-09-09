// ==========================================
// File: PhotoTensorValues.swift
// Spec: US-ING-004 AC-6; approved 4.0l tensor input semantics
// Task: 4.0l - Preserve Core ML tensor logical ordering
// Architecture: copy into Sendable values before leaving the prediction scope
// Generated: 2026-09-09
// ==========================================

import CoreML

nonisolated enum PhotoTensorValues {
    static func logicalFloats(_ array: MLMultiArray) -> [Float] {
        // MLMultiArray's logical subscript honors strides; raw storage may be transposed/padded.
        (0..<array.count).map { array[$0].floatValue }
    }
}
