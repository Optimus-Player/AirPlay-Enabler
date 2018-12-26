//
//  InjectedCode.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-25.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Darwin
import Foundation

struct InjectedCode {
   // MARK: - Initialization

   init(memoryData: MemoryData,
        absoluteAddressRanges: [Range<Int>] = [],
        externalSymbolInfos: [ExternalSymbolInfo] = []) {
      let count = memoryData.count
      precondition(InjectedCode.areRangesValid(absoluteAddressRanges, forDataCount: count))
      precondition(InjectedCode.areExternalSymbolInfosValid(externalSymbolInfos, forDataCount: count))

      self.memoryData = memoryData
      self.count = count

      self.absoluteAddressRanges = absoluteAddressRanges
      self.externalSymbolInfos = externalSymbolInfos
   }

   private static func areRangesValid(_ ranges: [Range<Int>],
                                      forDataCount dataCount: Int) -> Bool {
      return ranges.allSatisfy { isRangeValid($0, forDataCount: dataCount) }
   }

   private static func areExternalSymbolInfosValid(_ externalSymbolInfos: [ExternalSymbolInfo],
                                                   forDataCount dataCount: Int) -> Bool {
      return externalSymbolInfos.lazy
         .map { $0.absoluteAddressRange }
         .allSatisfy { isRangeValid($0, forDataCount: dataCount) }
   }

   private static func isRangeValid(_ range: Range<Int>, forDataCount dataCount: Int) -> Bool {
      if range.startIndex < 0 || range.endIndex > dataCount {
         return false
      }

      if range.count != 8 {  // 64-bit
         return false
      }

      return true
   }

   // MARK: - Properties

   private let memoryData: MemoryData
   let count: Int

   private let absoluteAddressRanges: [Range<Int>]
   private let externalSymbolInfos: [ExternalSymbolInfo]

   // MARK: - Making Data

   enum DataCreationError: Error {
      case unsupportedTargetByteOrder
      case failedToResolveExternalSymbol
   }

   func makeData(forExecutableDescribedBy executableInfo: ExecutableInfo) throws -> Data {
      let executableFileByteOrder = executableInfo.executableFileByteOrder
      guard var data = memoryData.data(in: executableFileByteOrder) else {
         throw DataCreationError.unsupportedTargetByteOrder
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

      for externalSymbolInfo in externalSymbolInfos {
         let absoluteAddressRange = externalSymbolInfo.absoluteAddressRange

         let currentAbsoluteAddressData = data[absoluteAddressRange]
         let newAbsoluteAddressData = try externalSymbolInfo.externalSymbolPointerData(fromExecutableDescribedBy: executableInfo)

         let addressSizeInBytes = absoluteAddressRange.count
         switch addressSizeInBytes {
         case 8:  // 64-bit
            os_log(.debug,
                   "Replacing absolute address 0x%llx with resolved external symbol absolute address 0x%llx.",
                   UInt64(source: currentAbsoluteAddressData,
                          sourceByteOrder: executableFileByteOrder),
                   UInt64(source: newAbsoluteAddressData,
                          sourceByteOrder: executableFileByteOrder))

         default:
            preconditionFailure("Unsupported absolute address size: \(addressSizeInBytes) bytes.")
         }

         data[absoluteAddressRange] = newAbsoluteAddressData
      }

      return Data(underlyingData: data,
                  rangesToIgnore: [])
   }
}

// MARK: -

fileprivate extension FixedWidthInteger where Self: UnsignedInteger {
   init(source data: Data, sourceByteOrder: NXByteOrder) {
      var source: Self = 0
      data.withUnsafeBytes { (pointer: UnsafePointer<Self>) in
         source = pointer.pointee
      }

      let needsByteSwap = NXHostByteOrder() != sourceByteOrder
      if needsByteSwap {
         self = source.byteSwapped
      } else {
         self = source
      }
   }

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
