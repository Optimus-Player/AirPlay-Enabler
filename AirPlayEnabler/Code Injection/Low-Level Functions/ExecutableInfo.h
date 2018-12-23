//
//  ExecutableInfo.h
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-12.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

@import Darwin;
@import Foundation;
@import MachO;

NS_ASSUME_NONNULL_BEGIN

struct ape_executable_info {
   vm_map_t task_vm_map NS_SWIFT_NAME(taskVMMap);

   mach_vm_address_t header_address_in_task_space NS_SWIFT_NAME(headerAddressInTaskSpace);
   mach_vm_offset_t aslr_offset NS_SWIFT_NAME(aslrOffset);

   struct mach_header_64 header;
   bool needs_byte_swap NS_SWIFT_NAME(needsByteSwap);

   mach_vm_address_t dyld_all_image_infos_address_in_task_space NS_SWIFT_NAME(dyldAllImageInfosAddressInTaskSpace);
} NS_SWIFT_NAME(ExecutableInfo);

kern_return_t ape_populate_executable_info(vm_map_t task_vm_map,
                                           const char *executable_file_path,
                                           struct ape_executable_info *executable_info_out) NS_SWIFT_NAME(ExecutableInfo.populateExecutableInfo(fromTaskVMDescribedBy:forExecutableFilePath:executableInfoOut:));

NS_ASSUME_NONNULL_END
