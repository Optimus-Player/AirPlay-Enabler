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

   init(littleEndianData: Data, absoluteAddressRanges: [Range<Int>] = []) {
      let count = littleEndianData.count

      precondition(MemoryData.areRangesValid(absoluteAddressRanges, forDataCount: count))

      self.littleEndianData = littleEndianData
      self.bigEndianData = nil
      self.count = count
      self.absoluteAddressRanges = absoluteAddressRanges
   }

   init(bigEndianData: Data, absoluteAddressRanges: [Range<Int>] = []) {
      let count = bigEndianData.count

      precondition(MemoryData.areRangesValid(absoluteAddressRanges, forDataCount: count))

      self.littleEndianData = nil
      self.bigEndianData = bigEndianData
      self.count = count
      self.absoluteAddressRanges = absoluteAddressRanges
   }

   init(littleEndianData: Data, bigEndianData: Data, absoluteAddressRanges: [Range<Int>] = []) {
      let count = littleEndianData.count

      precondition(count == bigEndianData.count)
      precondition(MemoryData.areRangesValid(absoluteAddressRanges, forDataCount: count))

      self.littleEndianData = littleEndianData
      self.bigEndianData = bigEndianData
      self.count = count
      self.absoluteAddressRanges = absoluteAddressRanges
   }

   private static func areRangesValid(_ ranges: [Range<Int>], forDataCount dataCount: Int) -> Bool {
      for range in ranges {
         if range.startIndex < 0 || range.endIndex > dataCount {
            return false
         }

         if range.count != 8 {  // 64-bit
            return false
         }
      }

      return true
   }

   // MARK: - Properties

   private let littleEndianData: Data?
   private let bigEndianData: Data?
   private let absoluteAddressRanges: [Range<Int>]

   let count: Int

   // MARK: - Retrieving Data

   func data(forExecutableDescribedBy executableInfo: ExecutableInfo) -> Data? {
      let executableFileByteOrder = executableInfo.executableFileByteOrder
      guard var data = self.data(in: executableFileByteOrder) else {
         return nil
      }

      let aslrOffset = executableInfo.aslrOffset

      for range in absoluteAddressRanges {
         var addressData = data[range]

         let addressSizeInBytes = range.count
         switch addressSizeInBytes {
         case 8:  // 64-bit
            UInt64.apply(aslrOffset: aslrOffset,
                         to: &addressData,
                         addressDataByteOrder: executableFileByteOrder)

         default:
            preconditionFailure("Unsupported absolute address size: \(addressSizeInBytes) bytes.")
         }

         data[range] = addressData
      }

      return data
   }

   private func data(in targetByteOrder: NXByteOrder) -> Data? {
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
      components.append("absoluteAddressRanges: \(absoluteAddressRanges)")

      return "MemoryData(\(components.joined(separator: ", ")))"
   }
}

fileprivate extension FixedWidthInteger where Self: UnsignedInteger {
   static func apply(aslrOffset: mach_vm_offset_t,
                     to addressData: inout Data,
                     addressDataByteOrder: NXByteOrder) {
      addressData.withUnsafeMutableBytes { (addressPointer: UnsafeMutablePointer<Self>) in
         let needsByteSwap = NXHostByteOrder() != addressDataByteOrder

         var address: Self
         if needsByteSwap {
            address = addressPointer.pointee.byteSwapped
         } else {
            address = addressPointer.pointee
         }

         let originalAddress = address
         address += Self(aslrOffset)

         os_log(.debug,
                "Applying ASLR offset 0x%llx to absolute address 0x%llx, which produces address 0x%llx.",
                aslrOffset,
                UInt64(originalAddress),
                UInt64(address))

         if needsByteSwap {
            addressPointer.pointee = address.byteSwapped
         } else {
            addressPointer.pointee = address
         }
      }
   }
}
