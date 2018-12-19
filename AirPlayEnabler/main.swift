//
//  main.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-11.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Dispatch
import Foundation
import os

os_log("AirPlayEnabler has started.")

let machServiceName = PrivilegedHelperInfo.shared.machServiceName
let xpcListener = NSXPCListener(machServiceName: machServiceName)

let xpcService = XPCService()
xpcListener.delegate = xpcService

DispatchQueue.main.async {
   OSInitiateActivity(named: "Initial Code Injection", flags: []) {
      try? CodeInjector.shared.injectCode()
   }

   os_log("Starting XPC listener for Mach service `%{public}@`.",
          machServiceName)
   xpcListener.resume()
}

dispatchMain()
