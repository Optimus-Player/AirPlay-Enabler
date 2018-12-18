//
//  TaskVM.h
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-12.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

@import Darwin;
@import Foundation;
@import MachO;

NS_ASSUME_NONNULL_BEGIN

struct ape_executable_header_context {
   vm_map_t task_vm_map NS_SWIFT_NAME(taskVMMap);

   mach_vm_address_t address_in_task_space NS_SWIFT_NAME(addressInTaskSpace);
   mach_vm_offset_t aslr_offset NS_SWIFT_NAME(aslrOffset);

   struct mach_header_64 header;
   bool needs_byte_swap NS_SWIFT_NAME(needsByteSwap);
} NS_SWIFT_NAME(ExecutableHeaderContext);

kern_return_t ape_read_executable_header(vm_map_t task_vm_map,
                                         struct ape_executable_header_context *executable_header_context_out) NS_SWIFT_NAME(ExecutableHeaderContext.readExecutableHeader(inTaskVMDescribedBy:executableHeaderContextOut:));

NS_ASSUME_NONNULL_END
