//
//  Errors.swift
//  AirPlayEnablerInterface
//
//  Created by Darren Mo on 2018-12-18.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Foundation

public protocol AirPlayEnablerInterfaceError: Error, RawRepresentable where RawValue == Int {
   static var errorDomain: NSErrorDomain { get }
}

extension NSError {
   public convenience init<ErrorType: AirPlayEnablerInterfaceError>(xpcServiceError: ErrorType) {
      self.init(domain: ErrorType.errorDomain as String,
                code: xpcServiceError.rawValue,
                userInfo: nil)
   }
}

extension AirPlayEnablerInterfaceError {
   public init?(nsError: NSError) {
      guard nsError.domain == Self.errorDomain as String else {
         return nil
      }
      self.init(rawValue: nsError.code)
   }
}
