//
//  ActivityTracing.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-25.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

func OSInitiateActivity<ReturnType>(named description: String,
                                    flags: APEOSActivityFlag = [],
                                    activityBlock: () throws -> ReturnType) rethrows -> ReturnType {
   func rethrowsHelper<ReturnType>(activityBlock: () throws -> ReturnType,
                                   rescue: ((Error) throws -> ReturnType)) rethrows -> ReturnType {
      var result: ReturnType?
      var error: Error?
      ape_os_activity_initiate(description, flags) {
         do {
            result = try activityBlock()
         } catch let activityBlockError {
            error = activityBlockError
         }
      }

      if let error = error {
         return try rescue(error)
      } else {
         return result!
      }
   }

   return try rethrowsHelper(activityBlock: activityBlock, rescue: { throw $0 })
}
