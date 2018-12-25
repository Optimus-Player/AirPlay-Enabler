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
        target: MemoryData,
        replacement: InjectedCode,
        originalMemoryProtection: vm_prot_t) {
      precondition(target.count == replacement.count)

      self.addressInExecutableFile = addressInExecutableFile
      self.requirements = requirements
      self.target = target
      self.replacement = replacement
      self.originalMemoryProtection = originalMemoryProtection
   }

   // MARK: - Properties

   private let addressInExecutableFile: mach_vm_address_t
   private let requirements: [Requirement]
   private let target: MemoryData
   private let replacement: InjectedCode
   private let originalMemoryProtection: vm_prot_t

   // MARK: - Applying/Unapplying the Patch

   enum PatchError: Error {
      case failedToReadTargetProcessMemory
      case unsupportedTargetByteOrder
      case failedToMakeInjectedCodeData(injectedCodeError: InjectedCode.DataCreationError)
      case requirementNotSatisfied
      case failedToFindTargetData
      case failedToModifyTargetDataMemoryProtection
      case failedToReplaceTargetData
      case failedToRestoreTargetData
      case failedToRestoreTargetDataMemoryProtection
   }

   func needsPatch(forExecutableDescribedBy executableInfo: ExecutableInfo) throws -> Bool {
      let replacementData = try self.makeReplacementData(forExecutableDescribedBy: executableInfo)
      return try _needsPatch(forExecutableDescribedBy: executableInfo,
                             replacementData: replacementData)
   }

   private func _needsPatch(forExecutableDescribedBy executableInfo: ExecutableInfo,
                            replacementData: InjectedCode.Data) throws -> Bool {
      let addressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
      guard let taskData = Data(contentsOf: addressInTaskSpace, byteCount: mach_vm_size_t(target.count), inTaskVMDescribedBy: executableInfo.taskVMMap) else {
         throw PatchError.failedToReadTargetProcessMemory
      }

      if taskData == replacementData {
         return false
      }

      let targetDataRequirement = Requirement(addressInExecutableFile: addressInExecutableFile,
                                              requiredMemoryData: target)
      guard try targetDataRequirement.isSatisfied(byExecutableDescribedBy: executableInfo) else {
         throw PatchError.failedToFindTargetData
      }

      return true
   }

   func apply(toExecutableDescribedBy executableInfo: ExecutableInfo) throws {
      let addressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
      let replacementData = try self.makeReplacementData(forExecutableDescribedBy: executableInfo)

      guard try _needsPatch(forExecutableDescribedBy: executableInfo, replacementData: replacementData) else {
         os_log("Target data at 0x%llx (in task space) has already been patched; skipping.",
                addressInTaskSpace)
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

      os_log(.info,
             "Patching task memory at address 0x%llx.",
             addressInTaskSpace)

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
      let addressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: addressInExecutableFile)
      let replacementData = try self.makeReplacementData(forExecutableDescribedBy: executableInfo)

      guard try !_needsPatch(forExecutableDescribedBy: executableInfo, replacementData: replacementData) else {
         os_log("Target data at 0x%llx (in task space) has not been patched; skipping.",
                addressInTaskSpace)
         return
      }

      os_log(.info,
             "Unapplying patch to task memory at address 0x%llx.",
             addressInTaskSpace)

      guard let targetData = target.data(in: executableInfo.executableFileByteOrder) else {
         throw PatchError.unsupportedTargetByteOrder
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

   private func makeReplacementData(forExecutableDescribedBy executableInfo: ExecutableInfo) throws -> InjectedCode.Data {
      do {
         return try replacement.makeData(forExecutableDescribedBy: executableInfo)
      } catch let error as InjectedCode.DataCreationError {
         throw PatchError.failedToMakeInjectedCodeData(injectedCodeError: error)
      } catch {
         fatalError("Caught error that is not of type `InjectedCode.DataCreationError`: \(error).")
      }
   }
}
