//
//  Patch+DynamicCreation.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-21.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Foundation

extension Patch {
   static func makePatchesForCurrentOperatingSystem() -> [Patch] {
      if ProcessInfo.processInfo.isOperatingSystemAtLeast(OperatingSystemVersion(majorVersion: 10, minorVersion: 14, patchVersion: 4)) {
         return Patch.makePatchesForMacOS10_14_4()
      } else {
         return Patch.makePatchesForMacOS10_14()
      }
   }
}
