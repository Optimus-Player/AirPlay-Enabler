//
//  XPCService.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-17.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import AirPlayEnablerInterface
import Foundation
import Security
import os

class XPCService: NSObject, NSXPCListenerDelegate {
   // MARK: - Initialization

   override init() {
      guard let codeSigningRequirements = Bundle.main.infoDictionary?["SMAuthorizedClients"] as? [String] else {
         preconditionFailure("Valid `SMAuthorizedClients` property not found in main bundle info dictionary.")
      }
      self.codeSigningRequirements = codeSigningRequirements.map { requirementText in
         var requirement: SecRequirement!
         var unmanagedError: Unmanaged<CFError>!
         let status = SecRequirementCreateWithStringAndErrors(requirementText as CFString,
                                                              [],
                                                              &unmanagedError,
                                                              &requirement)
         if status != errSecSuccess {
            let error = unmanagedError.takeRetainedValue()
            preconditionFailure("Code signing requirement text, `\(requirementText)`, is not valid: \(error).")
         }

         return (requirement, requirementText)
      }

      super.init()
   }

   // MARK: - Properties

   private let codeSigningRequirements: [(SecRequirement, String)]
   private let serviceImplementation = XPCServiceImplementation()

   // MARK: - XPC Listener Delegate

   func listener(_ listener: NSXPCListener,
                 shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
      // Note: Using the PID for authorization is racy because a new process could have replaced
      // the old process by the time we approve the XPC connection. However, in practice, this is
      // fine because if the old process was killed, the XPC connection would be closed.
      //
      // More info: https://forums.developer.apple.com/thread/72881#212532
      let clientPID = newConnection.processIdentifier

      os_log(.info,
             "Received connection request from process with PID %d.",
             clientPID)

      if !isClientAuthorized(clientPID) {
         return false
      }

      newConnection.exportedInterface = NSXPCInterface(with: AirPlayEnablerInterface.self)
      newConnection.exportedObject = serviceImplementation
      newConnection.resume()

      return true
   }

   // MARK: - Authorization

   private func isClientAuthorized(_ clientPID: pid_t) -> Bool {
      var clientCode: SecCode!
      let status = SecCodeCopyGuestWithAttributes(nil,
                                                  [kSecGuestAttributePid: clientPID] as CFDictionary,
                                                  [],
                                                  &clientCode)
      if status != errSecSuccess {
         os_log(.error,
                "SecCodeCopyGuestWithAttributes for PID %d returned error status code: %d.",
                clientPID,
                status)
         return false
      }

      for (requirement, requirementText) in codeSigningRequirements {
         var unmanagedError: Unmanaged<CFError>!
         let status = SecCodeCheckValidityWithErrors(clientCode,
                                                     [],
                                                     requirement,
                                                     &unmanagedError)
         if status == errSecSuccess {
            return true
         }

         let error = unmanagedError.takeRetainedValue()
         os_log(.error,
                "SecCodeCheckValidityWithErrors for PID %d and requirement `%{public}@` returned error: %{public}@.",
                clientPID,
                requirementText,
                String(describing: error))
      }

      return false
   }
}
