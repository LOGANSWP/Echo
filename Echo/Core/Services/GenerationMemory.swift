// ==========================================
// File: GenerationMemory.swift
// Spec: US-SYN-001/002/004; ADR-023 sections 1-4
// Task: 4.0k - Approved offline generation runtime
// AC coverage: pinned tokenizer, bounded inference and provenance grammar
// Architecture: AGENTS.md sections 4.2, 6.2; request-owned value types
// Generated: 2026-09-08
// ==========================================

import Darwin
import Foundation

nonisolated struct GenerationMemorySample: Encodable {
    let stage: String
    let residentBytes: UInt64
    let residentPeakBytes: UInt64
    let physicalFootprintBytes: UInt64
    let kernelPhysicalFootprintPeakBytes: Int64

    static func capture(_ stage: String) throws -> Self {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { buffer in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), buffer, &count)
            }
        }
        guard let peakOffset = MemoryLayout<task_vm_info_data_t>.offset(of: \.ledger_phys_footprint_peak),
            result == KERN_SUCCESS,
            Int(count) * MemoryLayout<integer_t>.size >= peakOffset + MemoryLayout<Int64>.size,
            info.ledger_phys_footprint_peak >= 0
        else { throw GenerationMemoryError.unavailable }
        return Self(
            stage: stage,
            residentBytes: info.resident_size,
            residentPeakBytes: info.resident_size_peak,
            physicalFootprintBytes: info.phys_footprint,
            kernelPhysicalFootprintPeakBytes: info.ledger_phys_footprint_peak
        )
    }
}

nonisolated enum GenerationMemoryError: Error { case unavailable, limit }
