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

guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
   preconditionFailure("Main bundle does not have bundle identifier.")
}
let xpcListener = NSXPCListener(machServiceName: bundleIdentifier)

let xpcService = XPCService()
xpcListener.delegate = xpcService

DispatchQueue.main.async {
   OSInitiateActivity(named: "Initial Code Injection", flags: []) {
      try? CodeInjector.shared.injectCode()
   }

   os_log("Starting XPC listener for Mach service `%{public}@`.",
          bundleIdentifier)
   xpcListener.resume()
}

dispatchMain()
