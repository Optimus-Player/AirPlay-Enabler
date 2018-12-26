//
//  Patch+MacOS10_14.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-21.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

extension Patch {
   static func makePatchesForMacOS10_14() -> [Patch] {
      return [
         Patch(addressInExecutableFile: 0x10000315f,
               requirements: [],
               target: MemoryData(littleEndianData: Data([0x45, 0x85, 0xe4, 0x74, 0x69])),
               replacement: InjectedCode(memoryData: MemoryData(littleEndianData: Data([0x45, 0x31, 0xe4, 0xeb, 0x69]))),
               originalMemoryProtection: VM_PROT_READ | VM_PROT_EXECUTE)
      ]
   }
}
