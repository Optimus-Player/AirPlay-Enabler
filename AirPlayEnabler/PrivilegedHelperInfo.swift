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

      self.machServiceName = bundleIdentifier
      self.launchdLabel = bundleIdentifier
      self.helperName = bundleIdentifier
   }

   // MARK: - Properties

   let machServiceName: String
   let launchdLabel: String
   let helperName: String
}
