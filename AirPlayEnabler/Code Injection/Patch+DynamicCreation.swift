//
//  Patch+DynamicCreation.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-21.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

extension Patch {
   static func makePatchesForCurrentOperatingSystem() -> [Patch] {
      return Patch.makePatchesForMacOS10_14()
   }
}
