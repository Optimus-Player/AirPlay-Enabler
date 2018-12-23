//
//  ExecutableInfo+ByteOrder.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-14.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Darwin

extension ExecutableInfo {
   var executableFileByteOrder: NXByteOrder {
      let hostByteOrder = NXHostByteOrder()

      if needsByteSwap {
         if hostByteOrder == NX_LittleEndian {
            return NX_BigEndian
         } else {
            return NX_LittleEndian
         }
      } else {
         return hostByteOrder
      }
   }
}
