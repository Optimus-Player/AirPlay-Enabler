//
//  InjectedCode+ExternalSymbolInfo.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-25.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Darwin
import Foundation

extension InjectedCode {
   struct ExternalSymbolInfo {
      init(absoluteAddressRange: Range<Int>,
           replaceWithPointerValueAt externalSymbolPointerAddressInExecutableFile: mach_vm_address_t) {
         self.absoluteAddressRange = absoluteAddressRange
         self.externalSymbolPointerAddressInExecutableFile = externalSymbolPointerAddressInExecutableFile
      }

      let absoluteAddressRange: Range<Int>
      let externalSymbolPointerAddressInExecutableFile: mach_vm_address_t

      func externalSymbolPointerData(fromExecutableDescribedBy executableInfo: ExecutableInfo) throws -> Foundation.Data {
         let externalSymbolPointerAddressInTaskSpace = executableInfo.addressInTaskSpace(fromAddressInExecutableFile: externalSymbolPointerAddressInExecutableFile)

         guard let data = Foundation.Data(contentsOf: externalSymbolPointerAddressInTaskSpace, byteCount: mach_vm_size_t(absoluteAddressRange.count), inTaskVMDescribedBy: executableInfo.taskVMMap) else {
            throw DataCreationError.failedToResolveExternalSymbol
         }

         return data
      }
   }
}
