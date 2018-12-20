//
//  XPCServiceImplementation+GetPrivilegedHelperVersion.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-20.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import AirPlayEnablerInterface

extension XPCServiceImplementation {
   func getPrivilegedHelperVersion(withReply reply: @escaping (_ version: PrivilegedHelperVersion) -> Void) {
      OSInitiateActivity(named: #function, flags: [.ifNonePresent]) {
         reply(PrivilegedHelperInfo.shared.version)
      }
   }
}
