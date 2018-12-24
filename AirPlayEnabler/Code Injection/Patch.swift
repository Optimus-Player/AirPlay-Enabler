//
//  Patch.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-21.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Darwin

struct Patch {
   // MARK: - Initialization

   init(addressInExecutableFile: mach_vm_address_t,
        requirements: [Requirement],
        targetMemoryData: MemoryData,
        replacementMemoryData: MemoryData,
        originalMemoryProtection: vm_prot_t) {
      precondition(targetMemoryData.count == replacementMemoryData.count)

      self.addressInExecutableFile = addressInExecutableFile
      self.requirements = requirements
      self.targetMemoryData = targetMemoryData
      self.replacementMemoryData = replacementMemoryData
      self.originalMemoryProtection = originalMemoryProtection
   }

   // MARK: - Properties

   private let addressInExecutableFile: mach_vm_address_t
   private let requirements: [Requirement]
   private let targetMemoryData: MemoryData
   private let replacementMemoryData: MemoryData
   private let originalMemoryProtection: vm_prot_t

   // MARK: - Applying/Unapplying the Patch

   enum PatchError: Error {
      case failedToReadTargetProcessMemory
      case failedToAccessMemoryData(memoryDataAccessError: MemoryData.AccessError)
      case requirementNotSatisfied
      case failedToFindTargetData
      case failedToModifyTargetDataMemoryProtection
      case failedToReplaceTargetData
      case failedToRestoreTargetData
      case failedToRestoreTargetDataMemoryProtection
   }

   func needsPatch(forExecutableDescribedBy executableInfo: ExecutableInfo) throws -> Bool {
      let replacementDataRequirement = Requirement(addressInExecutableFile: addressInExecutableFile,
                                                   requiredMemoryData: replacementMemoryData)
      if try replacementDataRequirement.isSatisfied(byExecutableDescribedBy: executableInfo) {
         return false
      }

      let targetDataRequirement = Requirement(addressInExecutableFile: addressInExecutableFile,
                                              requiredMemoryData: targetMemoryData)
      guard try targetDataRequirement.isSatisfied(byExecutableDescribedBy: executableInfo) else {
         throw PatchError.failedToFindTargetData
      }

      return true
   }

   func apply(toExecutableDescribedBy executableInfo: ExecutableInfo) throws {
      guard try needsPatch(forExecutableDescribedBy: executableInfo) else {
         os_log("Target data has already been patched; skipping.")
         return
      }

      for requirement in requirements {
         let isRequirementSatisfied = try requirement.isSatisfied(byExecutableDescribedBy: executableInfo)
         if !isRequirementSatisfied {
            os_log(.error,
                   "Requirement not satisfied: %{public}@.",
                   String(describing: requirement))
            throw PatchError.requirementNotSatisfied
         }
      }

      let addressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
      os_log(.info,
             "Patching task memory at address 0x%llx.",
             addressInTaskSpace)

      let replacementData: Data
      do {
         replacementData = try replacementMemoryData.data(forExecutableDescribedBy: executableInfo)
      } catch let error as MemoryData.AccessError {
         throw PatchError.failedToAccessMemoryData(memoryDataAccessError: error)
      }
      let replacementDataByteCount = replacementData.count

      let status = mach_vm_protect(executableInfo.taskVMMap,
                                   addressInTaskSpace,
                                   mach_vm_size_t(replacementDataByteCount),
                                   0,  // set_maximum: boolean_t
                                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)
      if status != KERN_SUCCESS {
         os_log(.error,
                "mach_vm_protect failed: %d.",
                status)
         throw PatchError.failedToModifyTargetDataMemoryProtection
      }

      try replacementData.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
         let status = mach_vm_write(executableInfo.taskVMMap,
                                    addressInTaskSpace,
                                    vm_offset_t(bitPattern: pointer),
                                    mach_msg_type_number_t(replacementDataByteCount))
         if status != KERN_SUCCESS {
            os_log(.error,
                   "mach_vm_write failed: %d.",
                   status)
            throw PatchError.failedToReplaceTargetData
         }
      }

      os_log("Successfully applied patch to 0x%llx (in task space).",
             addressInTaskSpace)
   }

   func unapply(toExecutableDescribedBy executableInfo: ExecutableInfo) throws {
      guard try !needsPatch(forExecutableDescribedBy: executableInfo) else {
         os_log("Target data has not been patched; skipping.")
         return
      }

      let addressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
      os_log(.info,
             "Unapplying patch to task memory at address 0x%llx.",
             addressInTaskSpace)

      let targetData: Data
      do {
         targetData = try targetMemoryData.data(forExecutableDescribedBy: executableInfo)
      } catch let error as MemoryData.AccessError {
         throw PatchError.failedToAccessMemoryData(memoryDataAccessError: error)
      }
      let targetDataByteCount = targetData.count

      try targetData.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
         let status = mach_vm_write(executableInfo.taskVMMap,
                                    addressInTaskSpace,
                                    vm_offset_t(bitPattern: pointer),
                                    mach_msg_type_number_t(targetDataByteCount))
         if status != KERN_SUCCESS {
            os_log(.error,
                   "mach_vm_write failed: %d.",
                   status)
            throw PatchError.failedToRestoreTargetData
         }
      }

      let status = mach_vm_protect(executableInfo.taskVMMap,
                                   addressInTaskSpace,
                                   mach_vm_size_t(targetDataByteCount),
                                   0,  // set_maximum: boolean_t
                                   originalMemoryProtection)
      if status != KERN_SUCCESS {
         os_log(.error,
                "mach_vm_protect failed: %d.",
                status)
         throw PatchError.failedToRestoreTargetDataMemoryProtection
      }

      os_log("Successfully unapplied patch to 0x%llx (in task space).",
             addressInTaskSpace)
   }
}
