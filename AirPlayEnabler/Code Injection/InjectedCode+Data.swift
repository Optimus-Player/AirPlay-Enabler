//
//  InjectedCode+Data.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-25.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Foundation

extension InjectedCode {
   struct Data {
      init(underlyingData: Foundation.Data, rangesToIgnore: [Range<Int>]) {
         self.underlyingData = underlyingData
         self.rangesToIgnore = rangesToIgnore.sorted { $0.startIndex < $1.startIndex }
      }

      private let underlyingData: Foundation.Data
      private let rangesToIgnore: [Range<Int>]

      var count: Int {
         return underlyingData.count
      }

      static func ==(lhs: Data, rhs: Foundation.Data) -> Bool {
         let count = lhs.underlyingData.count
         if count != rhs.count {
            return false
         }

         var lastIndex = 0
         for rangeToIgnore in lhs.rangesToIgnore {
            defer {
               lastIndex = rangeToIgnore.endIndex
            }

            if rangeToIgnore.startIndex <= lastIndex {
               continue
            }

            let rangeToCompare = lastIndex..<rangeToIgnore.startIndex
            if lhs.underlyingData[rangeToCompare] != rhs[rangeToCompare] {
               return false
            }
         }

         if lastIndex < count {
            let rangeToCompare = lastIndex..<count
            if lhs.underlyingData[rangeToCompare] != rhs[rangeToCompare] {
               return false
            }
         }

         return true
      }

      static func ==(lhs: Foundation.Data, rhs: Data) -> Bool {
         return rhs == lhs
      }

      func withUnsafeBytes<ContentType, ResultType>(body: (UnsafePointer<ContentType>) throws -> ResultType) rethrows -> ResultType {
         return try underlyingData.withUnsafeBytes(body)
      }
   }
}
