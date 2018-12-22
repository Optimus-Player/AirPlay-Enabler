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
      case unsupportedTargetProcessByteOrder
      case requirementNotSatisfied
      case failedToFindTargetData
      case failedToModifyTargetDataMemoryProtection
      case failedToReplaceTargetData
      case failedToRestoreTargetData
      case failedToRestoreTargetDataMemoryProtection
   }

   func needsPatch(forExecutableDescribedBy executableHeaderContext: ExecutableHeaderContext) throws -> Bool {
      let replacementDataRequirement = Requirement(addressInExecutableFile: addressInExecutableFile,
                                                   requiredMemoryData: replacementMemoryData)
      if try replacementDataRequirement.isSatisfied(byExecutableDescribedBy: executableHeaderContext) {
         return false
      }

      let targetDataRequirement = Requirement(addressInExecutableFile: addressInExecutableFile,
                                              requiredMemoryData: targetMemoryData)
      guard try targetDataRequirement.isSatisfied(byExecutableDescribedBy: executableHeaderContext) else {
         throw PatchError.failedToFindTargetData
      }

      return true
   }

   func apply(toExecutableDescribedBy executableHeaderContext: ExecutableHeaderContext) throws {
      guard try needsPatch(forExecutableDescribedBy: executableHeaderContext) else {
         os_log("Target data has already been patched; skipping.")
         return
      }

      for requirement in requirements {
         let isRequirementSatisfied = try requirement.isSatisfied(byExecutableDescribedBy: executableHeaderContext)
         if !isRequirementSatisfied {
            os_log(.error,
                   "Requirement not satisfied: %{public}@.",
                   String(describing: requirement))
            throw PatchError.requirementNotSatisfied
         }
      }

      let addressInTaskSpace = executableHeaderContext.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
      os_log(.info,
             "Patching task memory at address 0x%llx.",
             addressInTaskSpace)

      let executableFileByteOrder = executableHeaderContext.executableFileByteOrder
      guard let replacementData = replacementMemoryData.data(in: executableFileByteOrder) else {
         throw PatchError.unsupportedTargetProcessByteOrder
      }
      let replacementDataByteCount = replacementData.count

      let status = mach_vm_protect(executableHeaderContext.taskVMMap,
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
         let status = mach_vm_write(executableHeaderContext.taskVMMap,
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

   func unapply(toExecutableDescribedBy executableHeaderContext: ExecutableHeaderContext) throws {
      guard try !needsPatch(forExecutableDescribedBy: executableHeaderContext) else {
         os_log("Target data has not been patched; skipping.")
         return
      }

      let addressInTaskSpace = executableHeaderContext.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
      os_log(.info,
             "Unapplying patch to task memory at address 0x%llx.",
             addressInTaskSpace)

      let executableFileByteOrder = executableHeaderContext.executableFileByteOrder
      guard let targetData = targetMemoryData.data(in: executableFileByteOrder) else {
         throw PatchError.unsupportedTargetProcessByteOrder
      }
      let targetDataByteCount = targetData.count

      try targetData.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
         let status = mach_vm_write(executableHeaderContext.taskVMMap,
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

      let status = mach_vm_protect(executableHeaderContext.taskVMMap,
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
