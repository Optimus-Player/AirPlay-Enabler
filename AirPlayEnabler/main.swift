//
//  main.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-11.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Dispatch
import os

os_log("AirPlayEnabler has started.")

DispatchQueue.main.async {
   OSInitiateActivity(named: "Initial Code Injection", flags: []) {
      try? CodeInjector.shared.injectCode()
   }
}

dispatchMain()
