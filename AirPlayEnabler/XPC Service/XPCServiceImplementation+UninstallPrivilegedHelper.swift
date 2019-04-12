//
//  XPCServiceImplementation+UninstallPrivilegedHelper.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-18.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import AirPlayEnablerInterface
import Foundation
import os

extension XPCServiceImplementation {
   func uninstallPrivilegedHelper(withReply reply: @escaping (NSError) -> Void) {
      OSInitiateActivity(named: "\(type(of: self)).\(#function)") {
         _uninstallPrivilegedHelper(withReply: reply)
      }
   }

   private func _uninstallPrivilegedHelper(withReply reply: @escaping (NSError) -> Void) {
      let launchdPlistPath = "/Library/LaunchDaemons/\(PrivilegedHelperInfo.shared.helperName).plist"

      do {
         let launchdPlist = try LaunchdPlist(contentsOf: launchdPlistPath)
         let programPath = try launchdPlist.determineProgramPath()

         try XPCServiceImplementation.deleteLaunchdPlist(at: launchdPlistPath)
         try XPCServiceImplementation.deleteProgram(at: programPath)
         try XPCServiceImplementation.removeCodeInjection()
         try XPCServiceImplementation.unregisterPrivilegedHelperInLaunchd()
      } catch let error as UninstallPrivilegedHelperError {
         let nsError = NSError(xpcServiceError: error)
         reply(nsError)
      } catch {
         fatalError("Caught error that is not of type `UninstallPrivilegedHelperError`: \(error).")
      }
   }

   private struct LaunchdPlist: Decodable {
      let programAbsolutePath: String?
      let programArguments: [String]?

      enum CodingKeys: String, CodingKey {
         case programAbsolutePath = "Program"
         case programArguments = "ProgramArguments"
      }

      init(contentsOf launchdPlistPath: String) throws {
         let launchdPlistData: Data
         do {
            launchdPlistData = try Data(contentsOf: URL(fileURLWithPath: launchdPlistPath))
         } catch {
            os_log(.fault,
                   "Failed to read `%{public}@`: %{public}@.",
                   launchdPlistPath,
                   String(describing: error))
            throw UninstallPrivilegedHelperError.failedToReadLaunchdPlist
         }

         let propertyListDecoder = PropertyListDecoder()
         do {
            self = try propertyListDecoder.decode(type(of: self),
                                                  from: launchdPlistData)
         } catch {
            os_log(.fault,
                   "Failed to decode contents of `%{public}@`: %{public}@.",
                   launchdPlistPath,
                   String(describing: error))
            throw UninstallPrivilegedHelperError.failedToDecodeLaunchdPlist
         }
      }

      func determineProgramPath() throws -> String {
         if let programAbsolutePath = programAbsolutePath {
            return programAbsolutePath
         } else if let programArguments = programArguments, !programArguments.isEmpty {
            let programPath = programArguments[0]
            guard (programPath as NSString).isAbsolutePath else {
               os_log(.error,
                      "The first argument of the `ProgramArguments` property (in the launchd plist) is a relative path, which we do not support: `%{public}@`.",
                      programPath)
               throw UninstallPrivilegedHelperError.unsupportedLaunchdPlistProgramArguments
            }

            return programPath
         } else {
            os_log(.fault,
                   "The launchd plist does not contain the path to the program.")
            throw UninstallPrivilegedHelperError.failedToFindProgramPathInLaunchdPlist
         }
      }
   }

   private static func deleteLaunchdPlist(at launchdPlistPath: String) throws {
      do {
         try FileManager.default.removeItem(at: URL(fileURLWithPath: launchdPlistPath))
      } catch {
         os_log(.fault,
                "Failed to delete `%{public}@`: %{public}@.",
                launchdPlistPath,
                String(describing: error))
         throw UninstallPrivilegedHelperError.failedToDeleteLaunchdPlist
      }

      os_log("Deleted `%{public}@`.",
             launchdPlistPath)
   }

   private static func deleteProgram(at programPath: String) throws {
      do {
         try FileManager.default.removeItem(at: URL(fileURLWithPath: programPath))
      } catch {
         os_log(.fault,
                "Failed to delete `%{public}@`: %{public}@.",
                programPath,
                String(describing: error))
         throw UninstallPrivilegedHelperError.failedToDeleteProgram
      }

      os_log("Deleted `%{public}@`.",
             programPath)
   }

   private static func removeCodeInjection() throws {
      do {
         try CodeInjector.shared.removeCodeInjection()
      } catch CodeInjector.InjectError.failedToUnapplyPatch(patchError: .failedToFindTargetData) {
         os_log(.error,
                "Failed to find the patched data nor the original data. Ignoring since this is a success from an uninstallation perspective.")
      } catch {
         throw UninstallPrivilegedHelperError.failedToRemoveCodeInjection
      }

      os_log("Removed code injection.")
   }

   private static let timeoutInSecondsWaitingForLaunchdToKillUs: UInt32 = 5

   private static func unregisterPrivilegedHelperInLaunchd() throws -> Never {
      let launchctlExecutablePath = "/bin/launchctl"

      let launchctlProcess = Process()
      launchctlProcess.executableURL = URL(fileURLWithPath: launchctlExecutablePath)
      launchctlProcess.arguments = [
         "remove",
         PrivilegedHelperInfo.shared.launchdLabel
      ]

      os_log("Unregistering the privileged helper in launchd.")

      do {
         try launchctlProcess.run()
      } catch {
         os_log(.fault,
                "Failed to run `%{public}@`: %{public}@.",
                launchctlExecutablePath,
                String(describing: error))
         throw UninstallPrivilegedHelperError.failedToRunLaunchctlProcess
      }
      launchctlProcess.waitUntilExit()

      guard launchctlProcess.terminationReason == .exit else {
         os_log(.fault,
                "`%{public}@` was killed by an uncaught signal.",
                launchctlExecutablePath)
         throw UninstallPrivilegedHelperError.launchctlFailed
      }

      let launchctlStatus = launchctlProcess.terminationStatus
      guard launchctlStatus == 0 else {
         os_log(.fault,
                "`%{public}@` failed: %d.",
                launchctlExecutablePath,
                launchctlStatus)
         throw UninstallPrivilegedHelperError.launchctlFailed
      }

      sleep(timeoutInSecondsWaitingForLaunchdToKillUs)

      throw UninstallPrivilegedHelperError.timedOutWaitingForLaunchdToKillPrivilegedHelper
   }
}
