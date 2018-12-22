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
      case failedToApplyPatch(patchError: Patch.PatchError)
      case failedToUnapplyPatch(patchError: Patch.PatchError)
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

         let patches = Patch.makePatchesForCurrentOperatingSystem()
         for patch in patches {
            let needsPatch = try patch.needsPatch(forExecutableDescribedBy: executableHeaderContext)
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

            let patches = Patch.makePatchesForCurrentOperatingSystem()
            for patch in patches {
               try patch.apply(toExecutableDescribedBy: executableHeaderContext)
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

            let patches = Patch.makePatchesForCurrentOperatingSystem()
            for patch in patches.lazy.reversed() {
               try patch.unapply(toExecutableDescribedBy: executableHeaderContext)
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
}
