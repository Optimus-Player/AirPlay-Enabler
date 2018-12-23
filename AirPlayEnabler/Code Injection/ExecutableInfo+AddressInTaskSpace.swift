//
//  ExecutableInfo+AddressInTaskSpace.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-21.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

extension ExecutableInfo {
   func addressInTaskSpace(fromAddressInExecutableFile addressInExecutableFile: mach_vm_address_t) -> mach_vm_address_t {
      return addressInExecutableFile + aslrOffset
   }
}
