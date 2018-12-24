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

   init(littleEndianData: Data,
        absoluteAddressRanges: [Range<Int>] = [],
        externalSymbolInfos: [ExternalSymbolInfo] = []) {
      let count = littleEndianData.count

      precondition(MemoryData.areRangesValid(absoluteAddressRanges, forDataCount: count))
      precondition(MemoryData.areExternalSymbolInfosValid(externalSymbolInfos, forDataCount: count))

      self.littleEndianData = littleEndianData
      self.bigEndianData = nil
      self.count = count

      self.absoluteAddressRanges = absoluteAddressRanges
      self.externalSymbolInfos = externalSymbolInfos
   }

   init(bigEndianData: Data,
        absoluteAddressRanges: [Range<Int>] = [],
        externalSymbolInfos: [ExternalSymbolInfo] = []) {
      let count = bigEndianData.count

      precondition(MemoryData.areRangesValid(absoluteAddressRanges, forDataCount: count))
      precondition(MemoryData.areExternalSymbolInfosValid(externalSymbolInfos, forDataCount: count))

      self.littleEndianData = nil
      self.bigEndianData = bigEndianData
      self.count = count

      self.absoluteAddressRanges = absoluteAddressRanges
      self.externalSymbolInfos = externalSymbolInfos
   }

   init(littleEndianData: Data,
        bigEndianData: Data,
        absoluteAddressRanges: [Range<Int>] = [],
        externalSymbolInfos: [ExternalSymbolInfo] = []) {
      let count = littleEndianData.count

      precondition(count == bigEndianData.count)
      precondition(MemoryData.areRangesValid(absoluteAddressRanges, forDataCount: count))
      precondition(MemoryData.areExternalSymbolInfosValid(externalSymbolInfos, forDataCount: count))

      self.littleEndianData = littleEndianData
      self.bigEndianData = bigEndianData
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

   private let littleEndianData: Data?
   private let bigEndianData: Data?
   let count: Int

   private let absoluteAddressRanges: [Range<Int>]
   private let externalSymbolInfos: [ExternalSymbolInfo]

   // MARK: - Retrieving Data

   enum AccessError: Error {
      case unsupportedTargetByteOrder
      case failedToResolveExternalSymbol
   }

   func data(forExecutableDescribedBy executableInfo: ExecutableInfo) throws -> Data {
      let executableFileByteOrder = executableInfo.executableFileByteOrder
      var data = try self.data(in: executableFileByteOrder)

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

      return data
   }

   private func data(in targetByteOrder: NXByteOrder) throws -> Data {
      switch targetByteOrder {
      case NX_LittleEndian:
         guard let littleEndianData = littleEndianData else {
            throw AccessError.unsupportedTargetByteOrder
         }
         return littleEndianData

      case NX_BigEndian:
         guard let bigEndianData = bigEndianData else {
            throw AccessError.unsupportedTargetByteOrder
         }
         return bigEndianData

      default:
         throw AccessError.unsupportedTargetByteOrder
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

// MARK: -

extension MemoryData {
   struct ExternalSymbolInfo {
      init(absoluteAddressRange: Range<Int>,
           replaceWithPointerValueAt externalSymbolPointerAddressInExecutableFile: mach_vm_address_t) {
         self.absoluteAddressRange = absoluteAddressRange
         self.externalSymbolPointerAddressInExecutableFile = externalSymbolPointerAddressInExecutableFile
      }

      let absoluteAddressRange: Range<Int>
      let externalSymbolPointerAddressInExecutableFile: mach_vm_address_t

      fileprivate func externalSymbolPointerData(fromExecutableDescribedBy executableInfo: ExecutableInfo) throws -> Data {
         let externalSymbolPointerAddressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: externalSymbolPointerAddressInExecutableFile)

         guard let data = Data(contentsOf: externalSymbolPointerAddressInTaskSpace, byteCount: mach_vm_size_t(absoluteAddressRange.count), inTaskVMDescribedBy: executableInfo.taskVMMap) else {
            throw AccessError.failedToResolveExternalSymbol
         }

         return data
      }
   }
}
