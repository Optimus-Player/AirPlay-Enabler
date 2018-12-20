//
//  PrivilegedHelperInfo.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-18.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Foundation

struct PrivilegedHelperInfo {
   // MARK: - Initialization

   static let shared = PrivilegedHelperInfo()

   private init() {
      // TODO: Extract the actual values from the embedded launchd plist to avoid
      // mismatches.
      guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
         preconditionFailure("Main bundle does not have bundle identifier.")
      }

      let authorizedClientsKey = "SMAuthorizedClients"
      guard let clientCodeSigningRequirements = Bundle.main.infoDictionary?[authorizedClientsKey] as? [String] else {
         preconditionFailure("Valid `\(authorizedClientsKey)` property not found in main bundle info dictionary.")
      }

      self.machServiceName = bundleIdentifier
      self.launchdLabel = bundleIdentifier
      self.helperName = bundleIdentifier

      self.clientCodeSigningRequirements = clientCodeSigningRequirements
   }

   // MARK: - Properties

   let machServiceName: String
   let launchdLabel: String
   let helperName: String

   let clientCodeSigningRequirements: [String]
}
