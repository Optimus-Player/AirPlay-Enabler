//
//  PrivilegedHelperInfo.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-18.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import AirPlayEnablerInterface
import Foundation

struct PrivilegedHelperInfo {
   // MARK: - Initialization

   static let shared = PrivilegedHelperInfo()

   private init() {
      guard let infoDictionary = Bundle.main.infoDictionary else {
         preconditionFailure("Main bundle does not have info dictionary.")
      }

      let buildNumberKey = "CFBundleVersion"
      guard let buildNumberString = infoDictionary[buildNumberKey] as? String else {
         preconditionFailure("Valid `\(buildNumberKey)` property not found in main bundle info dictionary.")
      }

      let versionKey = "CFBundleShortVersionString"
      guard let versionString = infoDictionary[versionKey] as? String else {
         preconditionFailure("Valid `\(versionKey)` property not found in main bundle info dictionary.")
      }

      guard let version = PrivilegedHelperVersion(buildNumberString: buildNumberString, versionString: versionString) else {
         preconditionFailure("Build number string `\(buildNumberString)` and/or version string `\(versionString)` is invalid.")
      }

      // TODO: Extract the actual values from the embedded launchd plist to avoid
      // mismatches.
      guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
         preconditionFailure("Main bundle does not have bundle identifier.")
      }

      let authorizedClientsKey = "SMAuthorizedClients"
      guard let clientCodeSigningRequirements = infoDictionary[authorizedClientsKey] as? [String] else {
         preconditionFailure("Valid `\(authorizedClientsKey)` property not found in main bundle info dictionary.")
      }

      self.version = version

      self.machServiceName = bundleIdentifier
      self.launchdLabel = bundleIdentifier
      self.helperName = bundleIdentifier

      self.clientCodeSigningRequirements = clientCodeSigningRequirements
   }

   // MARK: - Properties

   let version: PrivilegedHelperVersion

   let machServiceName: String
   let launchdLabel: String
   let helperName: String

   let clientCodeSigningRequirements: [String]
}
