//
//  Patch+Requirement.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-21.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Darwin
import Foundation

extension Patch {
   struct Requirement {
      // MARK: - Initialization

      init(addressInExecutableFile: mach_vm_address_t,
           requiredMemoryData: MemoryData) {
         self.addressInExecutableFile = addressInExecutableFile
         self.requiredMemoryData = requiredMemoryData
      }

      // MARK: - Properties

      private let addressInExecutableFile: mach_vm_address_t
      private let requiredMemoryData: MemoryData

      // MARK: - Checking Satisfaction

      func isSatisfied(byExecutableDescribedBy executableHeaderContext: ExecutableHeaderContext) throws -> Bool {
         let addressInTaskSpace = executableHeaderContext.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
         os_log(.info,
                "Reading task memory at address 0x%llx.",
                addressInTaskSpace)

         var bufferAddress: vm_offset_t = 0
         let requestedBufferByteCount = mach_vm_size_t(requiredMemoryData.count)
         var bufferByteCount: mach_msg_type_number_t = 0
         let status = mach_vm_read(executableHeaderContext.taskVMMap,
                                   addressInTaskSpace,
                                   requestedBufferByteCount,
                                   &bufferAddress,
                                   &bufferByteCount)
         if status != KERN_SUCCESS {
            os_log(.error,
                   "mach_vm_read failed: %d.",
                   status)
            throw PatchError.failedToReadTargetProcessMemory
         } else if bufferByteCount != requestedBufferByteCount {
            os_log(.error,
                   "mach_vm_read returned data size (%{iec-bytes}u) that is different from the requested data size (%{iec-bytes}llu).",
                   bufferByteCount,
                   requestedBufferByteCount);
            throw PatchError.failedToReadTargetProcessMemory
         }

         guard let bufferPointer = UnsafeMutableRawPointer(bitPattern: bufferAddress) else {
            os_log(.fault,
                   "mach_vm_read returned NULL pointer.")
            throw PatchError.failedToReadTargetProcessMemory
         }
         let buffer = Data(bytesNoCopy: bufferPointer,
                           count: Int(bufferByteCount),
                           deallocator: .virtualMemory)
         os_log(.info,
                "Task memory: %{public}@.",
                (buffer as NSData).description)

         let executableFileByteOrder = executableHeaderContext.executableFileByteOrder
         guard let requiredData = requiredMemoryData.data(in: executableFileByteOrder) else {
            throw PatchError.unsupportedTargetProcessByteOrder
         }

         return buffer == requiredData
      }
   }
}
