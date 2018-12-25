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

      func isSatisfied(byExecutableDescribedBy executableInfo: ExecutableInfo) throws -> Bool {
         let addressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
         guard let taskData = Data(contentsOf: addressInTaskSpace, byteCount: mach_vm_size_t(requiredMemoryData.count), inTaskVMDescribedBy: executableInfo.taskVMMap) else {
            throw PatchError.failedToReadTargetProcessMemory
         }

         guard let requiredData = requiredMemoryData.data(in: executableInfo.executableFileByteOrder) else {
            throw PatchError.unsupportedTargetByteOrder
         }

         return taskData == requiredData
      }
   }
}
