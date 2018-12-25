//
//  MemoryData.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-21.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Foundation

struct MemoryData: CustomStringConvertible {
   // MARK: - Initialization

   init(littleEndianData: Data) {
      self.littleEndianData = littleEndianData
      self.bigEndianData = nil
      self.count = littleEndianData.count
   }

   init(bigEndianData: Data) {
      self.littleEndianData = nil
      self.bigEndianData = bigEndianData
      self.count = bigEndianData.count
   }

   init(littleEndianData: Data,
        bigEndianData: Data) {
      let count = littleEndianData.count
      precondition(count == bigEndianData.count)

      self.littleEndianData = littleEndianData
      self.bigEndianData = bigEndianData
      self.count = count
   }

   // MARK: - Properties

   private let littleEndianData: Data?
   private let bigEndianData: Data?
   let count: Int

   // MARK: - Retrieving Data

   func data(in targetByteOrder: NXByteOrder) -> Data? {
      switch targetByteOrder {
      case NX_LittleEndian:
         guard let littleEndianData = littleEndianData else {
            return nil
         }
         return littleEndianData

      case NX_BigEndian:
         guard let bigEndianData = bigEndianData else {
            return nil
         }
         return bigEndianData

      default:
         return nil
      }
   }

   // MARK: - CustomStringConvertible Conformance

   var description: String {
      var components = [String]()

      if let littleEndianData = littleEndianData {
         components.append("littleEndianData: \((littleEndianData as NSData).description)")
      }
      if let bigEndianData = bigEndianData {
         components.append("bigEndianData: \((bigEndianData as NSData).description)")
      }

      return "MemoryData(\(components.joined(separator: ", ")))"
   }
}
