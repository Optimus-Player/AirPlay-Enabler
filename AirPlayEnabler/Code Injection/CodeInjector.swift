//
//  CodeInjector.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-12.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Darwin
import Foundation
import MachO
import os

class CodeInjector {
   // MARK: - Initialization

   static let shared = CodeInjector()

   private init() {
   }

   private let serialQueue = DispatchQueue(label: "Code Injector Queue")

   // MARK: - Errors

   enum InjectError: Error {
      case pgrepProcessRunError(underlyingError: Error)
      case invalidPgrepOutput(output: Data)
      case failedToFindTargetProcess
      case tooManyTargetProcesses
      case failedToAttachToTargetProcess
      case failedToReadExecutableHeader
      case failedToReadTargetProcessMemory
      case failedToFindTargetInstructions
      case failedToModifyTargetInstructionsMemoryProtection
      case failedToReplaceTargetInstructions
      case failedToRestoreTargetInstructions
      case failedToRestoreTargetInstructionsMemoryProtection
   }
   private(set) var latestError: InjectError?

   // MARK: - Initializing the Executable Header Context

   private var _executableHeaderContext: ExecutableHeaderContext?
   private func executableHeaderContext() throws -> ExecutableHeaderContext {
      if let executableHeaderContext = _executableHeaderContext {
         os_log(.info, "Executable header context has been previously found; reusing.")
         return executableHeaderContext
      }

      os_log("Executable header context not found; will try to populate it.")

      let amfidPIDs = try CodeInjector.findPIDs(forProcessesNamed: "amfid")
      guard !amfidPIDs.isEmpty else {
         throw InjectError.failedToFindTargetProcess
      }
      guard amfidPIDs.count == 1 else {
         os_log(.error, "Unexpectedly found multiple amfid PIDs.")
         throw InjectError.tooManyTargetProcesses
      }

      let amfidPID = amfidPIDs.first!
      os_log("Found amfid PID: %d.", amfidPID);

      let executableHeaderContext: ExecutableHeaderContext
      do {
         executableHeaderContext = try CodeInjector.readExecutableHeader(inProcessIdentifiedBy: amfidPID)
      } catch let error as InjectError {
         latestError = error
         throw error
      }

      _executableHeaderContext = executableHeaderContext
      os_log("Successfully populated executable header context.")

      return executableHeaderContext
   }

   // MARK: - Patches

   private static func makePatches() -> [Patch] {
      return [
         Patch(addressInExecutableFile: 0x10000315f,
               targetInstructionsInLittleEndian: [Data([0x45, 0x85, 0xe4]),
                                                  Data([0x74, 0x69])],
               replacementInstructionsInLittleEndian: [Data([0x45, 0x31, 0xe4]),
                                                       Data([0xeb, 0x69])])
      ]
   }

   // MARK: - Checking Activation Status

   func isCodeInjectionActive() -> Bool {
      var isCodeInjectionActive = false
      serialQueue.sync {
         isCodeInjectionActive = _isCodeInjectionActive()
      }
      return isCodeInjectionActive
   }

   private func _isCodeInjectionActive() -> Bool {
      do {
         let executableHeaderContext = try self.executableHeaderContext()

         let patches = CodeInjector.makePatches()
         for patch in patches {
            let needsPatch = try CodeInjector.needsPatch(patch,
                                                         forExecutableDescribedBy: executableHeaderContext)
            if needsPatch {
               return false
            }
         }

         return true
      } catch {
         os_log(.error,
                "Failed to check code injection activation status: %{public}@; assuming code injection is inactive.",
                String(describing: error))
         return false
      }
   }

   // MARK: - Injecting Code

   func injectCode() throws {
      try serialQueue.sync {
         try _injectCode()
      }
   }

   private func _injectCode() throws {
      os_log("Starting code injection.")

      do {
         do {
            let executableHeaderContext = try self.executableHeaderContext()

            let patches = CodeInjector.makePatches()
            for patch in patches {
               try CodeInjector.apply(patch,
                                      toExecutableDescribedBy: executableHeaderContext)
            }
         } catch {
            os_log(.error, "Failed to inject code: %{public}@.", String(describing: error))
            throw error
         }
      } catch let error as InjectError {
         latestError = error
         throw error
      }

      os_log("Successfully finished code injection.")
   }

   func removeCodeInjection() throws {
      try serialQueue.sync {
         try _removeCodeInjection()
      }
   }

   private func _removeCodeInjection() throws {
      os_log("Starting removal of code injection.")

      do {
         do {
            let executableHeaderContext = try self.executableHeaderContext()

            let patches = CodeInjector.makePatches()
            for patch in patches.lazy.reversed() {
               try CodeInjector.unapply(patch,
                                        toExecutableDescribedBy: executableHeaderContext)
            }
         } catch {
            os_log(.error, "Failed to remove code injection: %{public}@.", String(describing: error))
            throw error
         }
      } catch let error as InjectError {
         latestError = error
         throw error
      }

      os_log("Successfully finished removing code injection.")
   }
}

// MARK: - Underlying Implementation

extension CodeInjector {
   private static func findPIDs(forProcessesNamed processName: String) throws -> [pid_t] {
      os_log(.info,
             "Trying to find processes named `%{public}@`.",
             processName)

      let pgrepProcess = Process()
      pgrepProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
      pgrepProcess.arguments = ["^\(processName)$"]

      let standardOutputPipe = Pipe()
      pgrepProcess.standardOutput = standardOutputPipe

      do {
         try pgrepProcess.run()
      } catch {
         os_log(.fault,
                "Failed to run pgrep process: %{public}@.",
                String(describing: error))
         throw error
      }
      pgrepProcess.waitUntilExit()

      let standardOutputData = standardOutputPipe.fileHandleForReading.readDataToEndOfFile()
      guard let standardOutputString = String(data: standardOutputData, encoding: .utf8) else {
         os_log(.error,
                "The pgrep process sent non-UTF-8-encoded data to its standard output: %{public}@.",
                (standardOutputData as NSData).description)
         throw InjectError.invalidPgrepOutput(output: standardOutputData)
      }

      let pidStrings = standardOutputString.split(separator: "\n")
      let pids = try pidStrings.map { (pidString) -> pid_t in
         guard let pid = pid_t(pidString) else {
            os_log(.fault,
                   "The pgrep process sent an incorrectly-formatted PID string to its standard output: %{public}@.",
                   String(pidString))
            throw InjectError.invalidPgrepOutput(output: standardOutputData)
         }
         return pid
      }

      return pids
   }

   private static func readExecutableHeader(inProcessIdentifiedBy targetPID: pid_t) throws -> ExecutableHeaderContext {
      var targetTask: mach_port_name_t = 0
      var status = task_for_pid(mach_task_self_, targetPID, &targetTask)
      if status != KERN_SUCCESS {
         os_log(.error,
                "task_for_pid failed: %d.",
                status)
         throw InjectError.failedToAttachToTargetProcess
      }

      var executableHeaderContext = ExecutableHeaderContext()
      status = ExecutableHeaderContext.readExecutableHeader(inTaskVMDescribedBy: targetTask,
                                                            executableHeaderContextOut: &executableHeaderContext)
      if status != KERN_SUCCESS {
         os_log(.error,
                "ExecutableHeaderContext.readExecutableHeader failed: %d.",
                status)
         throw InjectError.failedToReadExecutableHeader
      }

      return executableHeaderContext
   }

   private struct Patch {
      init(addressInExecutableFile: mach_vm_address_t,
           targetInstructionsInLittleEndian: [Data],
           replacementInstructionsInLittleEndian: [Data]) {
         self.addressInExecutableFile = addressInExecutableFile
         self.targetInstructionsInLittleEndian = targetInstructionsInLittleEndian
         self.replacementInstructionsInLittleEndian = replacementInstructionsInLittleEndian

         precondition(targetInstructionsByteCount == replacementInstructionsByteCount)
      }

      private let addressInExecutableFile: mach_vm_address_t

      func addressInTaskSpace(aslrOffset: mach_vm_offset_t) -> mach_vm_address_t {
         return addressInExecutableFile + aslrOffset
      }

      private let targetInstructionsInLittleEndian: [Data]
      private let replacementInstructionsInLittleEndian: [Data]

      var targetInstructionsByteCount: mach_vm_size_t {
         return Patch.byteCount(for: targetInstructionsInLittleEndian)
      }
      var replacementInstructionsByteCount: mach_vm_size_t {
         return Patch.byteCount(for: replacementInstructionsInLittleEndian)
      }
      private static func byteCount(for instructions: [Data]) -> mach_vm_size_t {
         return mach_vm_size_t(instructions.reduce(0) { $0 + $1.count })
      }

      func targetInstructions(in targetByteOrder: NXByteOrder) -> Data {
         return Patch.combining(targetInstructionsInLittleEndian,
                                targetByteOrder: targetByteOrder)
      }
      func replacementInstructions(in targetByteOrder: NXByteOrder) -> Data {
         return Patch.combining(replacementInstructionsInLittleEndian,
                                targetByteOrder: targetByteOrder)
      }
      private static func combining(_ instructionsInLittleEndian: [Data],
                                    targetByteOrder: NXByteOrder) -> Data {
         let needsByteSwap = targetByteOrder != NX_LittleEndian

         var combinedInstructions = Data()
         for instruction in instructionsInLittleEndian {
            if needsByteSwap {
               combinedInstructions.append(contentsOf: instruction.lazy.reversed())
            } else {
               combinedInstructions.append(contentsOf: instruction)
            }
         }

         return combinedInstructions
      }
   }

   private static func needsPatch(_ patch: Patch,
                                  forExecutableDescribedBy executableHeaderContext: ExecutableHeaderContext) throws -> Bool {
      let addressInTaskSpace = patch.addressInTaskSpace(aslrOffset: executableHeaderContext.aslrOffset)
      os_log(.info,
             "Reading task memory at address 0x%llx.",
             addressInTaskSpace)

      var bufferAddress: vm_offset_t = 0
      let requestedBufferByteCount = patch.targetInstructionsByteCount
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
         throw InjectError.failedToReadTargetProcessMemory
      } else if bufferByteCount != requestedBufferByteCount {
         os_log(.error,
                "mach_vm_read returned data size (%{iec-bytes}u) that is different from the requested data size (%{iec-bytes}llu).",
                bufferByteCount,
                requestedBufferByteCount);
         throw InjectError.failedToReadTargetProcessMemory
      }

      guard let bufferPointer = UnsafeMutableRawPointer(bitPattern: bufferAddress) else {
         os_log(.fault,
                "mach_vm_read returned NULL pointer.")
         throw InjectError.failedToReadTargetProcessMemory
      }
      let buffer = Data(bytesNoCopy: bufferPointer,
                        count: Int(bufferByteCount),
                        deallocator: .virtualMemory)
      os_log(.info,
             "Task memory: %{public}@.",
             (buffer as NSData).description)

      let executableFileByteOrder = executableHeaderContext.executableFileByteOrder

      let replacementInstructions = patch.replacementInstructions(in: executableFileByteOrder)
      if buffer == replacementInstructions {
         return false
      }

      let targetInstructions = patch.targetInstructions(in: executableFileByteOrder)
      guard buffer == targetInstructions else {
         os_log(.error,
                "Failed to find target instructions: %{public}@.",
                (targetInstructions as NSData).description)
         throw InjectError.failedToFindTargetInstructions
      }
      return true
   }

   private static func apply(_ patch: Patch,
                             toExecutableDescribedBy executableHeaderContext: ExecutableHeaderContext) throws {
      guard try needsPatch(patch, forExecutableDescribedBy: executableHeaderContext) else {
         os_log("Target instructions have already been patched; skipping.")
         return
      }

      let addressInTaskSpace = patch.addressInTaskSpace(aslrOffset: executableHeaderContext.aslrOffset)
      os_log(.info,
             "Patching task memory at address 0x%llx.",
             addressInTaskSpace)

      let executableFileByteOrder = executableHeaderContext.executableFileByteOrder
      let replacementInstructions = patch.replacementInstructions(in: executableFileByteOrder)

      let status = mach_vm_protect(executableHeaderContext.taskVMMap,
                                   addressInTaskSpace,
                                   mach_vm_size_t(replacementInstructions.count),
                                   0,  // set_maximum: boolean_t
                                   VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE)
      if status != KERN_SUCCESS {
         os_log(.error,
                "mach_vm_protect failed: %d.",
                status)
         throw InjectError.failedToModifyTargetInstructionsMemoryProtection
      }

      try replacementInstructions.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
         let status = mach_vm_write(executableHeaderContext.taskVMMap,
                                    addressInTaskSpace,
                                    vm_offset_t(bitPattern: pointer),
                                    mach_msg_type_number_t(replacementInstructions.count))
         if status != KERN_SUCCESS {
            os_log(.error,
                   "mach_vm_write failed: %d.",
                   status)
            throw InjectError.failedToReplaceTargetInstructions
         }
      }
   }

   private static func unapply(_ patch: Patch,
                               toExecutableDescribedBy executableHeaderContext: ExecutableHeaderContext) throws {
      guard try !needsPatch(patch, forExecutableDescribedBy: executableHeaderContext) else {
         os_log("Target instructions have not been patched; skipping.")
         return
      }

      let addressInTaskSpace = patch.addressInTaskSpace(aslrOffset: executableHeaderContext.aslrOffset)
      os_log(.info,
             "Unapplying patch to task memory at address 0x%llx.",
             addressInTaskSpace)

      let executableFileByteOrder = executableHeaderContext.executableFileByteOrder
      let targetInstructions = patch.targetInstructions(in: executableFileByteOrder)

      try targetInstructions.withUnsafeBytes { (pointer: UnsafePointer<UInt8>) in
         let status = mach_vm_write(executableHeaderContext.taskVMMap,
                                    addressInTaskSpace,
                                    vm_offset_t(bitPattern: pointer),
                                    mach_msg_type_number_t(targetInstructions.count))
         if status != KERN_SUCCESS {
            os_log(.error,
                   "mach_vm_write failed: %d.",
                   status)
            throw InjectError.failedToRestoreTargetInstructions
         }
      }

      let status = mach_vm_protect(executableHeaderContext.taskVMMap,
                                   addressInTaskSpace,
                                   mach_vm_size_t(targetInstructions.count),
                                   0,  // set_maximum: boolean_t
                                   VM_PROT_READ | VM_PROT_EXECUTE)
      if status != KERN_SUCCESS {
         os_log(.error,
                "mach_vm_protect failed: %d.",
                status)
         throw InjectError.failedToRestoreTargetInstructionsMemoryProtection
      }
   }
}
