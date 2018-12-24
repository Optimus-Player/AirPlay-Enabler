//
//  Data+TaskVM.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-24.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Darwin
import Foundation

extension Data {
   init?(contentsOf addressInTaskSpace: mach_vm_address_t,
         byteCount requestedBufferByteCount: mach_vm_size_t,
         inTaskVMDescribedBy taskVMMap: vm_map_t) {
      os_log(.info,
             "Reading task memory at address 0x%llx.",
             addressInTaskSpace)

      var bufferAddress: vm_offset_t = 0
      var bufferByteCount: mach_msg_type_number_t = 0
      let status = mach_vm_read(taskVMMap,
                                addressInTaskSpace,
                                requestedBufferByteCount,
                                &bufferAddress,
                                &bufferByteCount)
      if status != KERN_SUCCESS {
         os_log(.error,
                "mach_vm_read failed: %d.",
                status)
         return nil
      } else if bufferByteCount != requestedBufferByteCount {
         os_log(.error,
                "mach_vm_read returned size (%{iec-bytes}u) that is different from the requested size (%{iec-bytes}llu).",
                bufferByteCount,
                requestedBufferByteCount);
         return nil
      }

      guard let bufferPointer = UnsafeMutableRawPointer(bitPattern: bufferAddress) else {
         os_log(.fault,
                "mach_vm_read returned NULL pointer.")
         return nil
      }
      self.init(bytesNoCopy: bufferPointer,
                count: Int(bufferByteCount),
                deallocator: .virtualMemory)

      os_log(.info,
             "Task memory: %{public}@.",
             (self as NSData).description)
   }
}
