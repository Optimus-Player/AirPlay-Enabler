//
//  XPCServiceImplementation+IsPrivilegedHelperRunning.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-19.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

extension XPCServiceImplementation {
   func isPrivilegedHelperRunning(withReply reply: @escaping () -> Void) {
      OSInitiateActivity(named: "\(type(of: self)).\(#function)") {
         reply()
      }
   }
}
