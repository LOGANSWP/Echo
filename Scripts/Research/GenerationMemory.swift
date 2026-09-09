// Task 4.0k: same Darwin accounting used by the short-prefix research probe.
import Foundation
import Darwin

struct MemorySample: Encodable {
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

enum GenerationMemoryError: Error { case unavailable, limit }
