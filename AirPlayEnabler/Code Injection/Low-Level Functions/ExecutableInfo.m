//
//  ExecutableInfo.m
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-12.
//  Copyright © 2018 Darren Mo. All rights reserved.
//
//  Inspired by fG!: https://sourceforge.net/p/machoview/code/ci/master/tree/Attach.mm
//

#import "ExecutableInfo.h"

@import os.log;

#import "Common.h"
#import "ImageInfo.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: - Static Function Declarations

static kern_return_t read_executable_header_at_address(vm_map_t task_vm_map,
                                                       mach_vm_address_t address_in_task_space,
                                                       bool *is_supported_executable_out,
                                                       struct ape_executable_info *executable_info_out);
static kern_return_t determine_aslr_offset(vm_map_t task_vm_map,
                                           struct ape_executable_info *executable_info_inout);

// MARK: - Function Definitions

kern_return_t ape_populate_executable_info(vm_map_t task_vm_map,
                                           const char *executable_file_path,
                                           struct ape_executable_info *executable_info_out) {
   ENTER_FUNCTION();

   if (executable_file_path == NULL) {
      os_log_error(OS_LOG_DEFAULT, "executable_file_path should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }
   if (executable_info_out == NULL) {
      os_log_error(OS_LOG_DEFAULT, "executable_info_out should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }

   struct task_dyld_info dyld_info = {0};
   mach_msg_type_number_t task_info_count = TASK_DYLD_INFO_COUNT;
   kern_return_t status = task_info(task_vm_map,
                                    TASK_DYLD_INFO,
                                    (task_info_t)&dyld_info,
                                    &task_info_count);
   if (status != KERN_SUCCESS) {
      os_log_error(OS_LOG_DEFAULT,
                   "task_info failed: %d.",
                   status);
      EXIT_FUNCTION(KERN_FAILURE);
   } else if (task_info_count != TASK_DYLD_INFO_COUNT) {
      os_log_fault(OS_LOG_DEFAULT,
                   "task_info returned info count that does not correspond to task_dyld_info struct: %u.",
                   task_info_count);
      EXIT_FUNCTION(KERN_FAILURE);
   }

   integer_t dyld_all_image_infos_format = dyld_info.all_image_info_format;
   if (dyld_all_image_infos_format != TASK_DYLD_ALL_IMAGE_INFO_64) {
      os_log_error(OS_LOG_DEFAULT,
                   "Unsupported dyld_all_image_infos format: %d.",
                   dyld_all_image_infos_format);
      EXIT_FUNCTION(KERN_FAILURE);
   }

   mach_vm_address_t dyld_all_image_infos_address_in_task_space = dyld_info.all_image_info_addr;

   struct ape_image_info image_info = {0};
   status = ape_find_image_info(task_vm_map,
                                dyld_all_image_infos_address_in_task_space,
                                executable_file_path,
                                &image_info);
   if (status != KERN_SUCCESS) {
      os_log_error(OS_LOG_DEFAULT,
                   "ape_find_image_info failed: %d.",
                   status);
      EXIT_FUNCTION(KERN_FAILURE);
   }

   bool is_supported_executable = false;
   status = read_executable_header_at_address(task_vm_map,
                                              image_info.header_address_in_task_space,
                                              &is_supported_executable,
                                              executable_info_out);
   if (status != KERN_SUCCESS) {
      os_log_error(OS_LOG_DEFAULT,
                   "read_executable_header_at_address failed: %d.",
                   status);
      EXIT_FUNCTION(KERN_FAILURE);
   } else if (!is_supported_executable) {
      os_log_error(OS_LOG_DEFAULT,
                   "Unsupported executable format/architecture.");
      EXIT_FUNCTION(KERN_FAILURE);
   }

   executable_info_out->dyld_all_image_infos_address_in_task_space = dyld_all_image_infos_address_in_task_space;

   EXIT_FUNCTION(KERN_SUCCESS);
}

static kern_return_t read_executable_header_at_address(vm_map_t task_vm_map,
                                                       mach_vm_address_t address_in_task_space,
                                                       bool *is_supported_executable_out,
                                                       struct ape_executable_info *executable_info_out) {
   ENTER_FUNCTION();

   typeof(executable_info_out->header) header = {0};
   mach_vm_size_t requested_header_size = sizeof(typeof(header));
   mach_vm_size_t header_size = 0;

   kern_return_t status = mach_vm_read_overwrite(task_vm_map,
                                                 address_in_task_space,
                                                 requested_header_size,
                                                 (mach_vm_address_t)&header,
                                                 &header_size);
   if (status != KERN_SUCCESS) {
      os_log_error(OS_LOG_DEFAULT,
                   "mach_vm_read_overwrite failed: %d.",
                   status);
      EXIT_FUNCTION(KERN_FAILURE);
   } else if (header_size != requested_header_size) {
      os_log_error(OS_LOG_DEFAULT,
                   "mach_vm_read_overwrite returned size (%{iec-bytes}llu) that is different from the requested size (%{iec-bytes}llu).",
                   header_size,
                   requested_header_size);
      EXIT_FUNCTION(KERN_FAILURE);
   }

   bool needs_byte_swap = false;
   if (header.magic == MH_CIGAM_64) {
      needs_byte_swap = true;

      os_log_info(OS_LOG_DEFAULT,
                  "Found MH_CIGAM_64; swapping bytes in Mach-O header struct.");
      swap_mach_header_64(&header, NXHostByteOrder());
   }

   *is_supported_executable_out = false;
   if (header.magic == MH_MAGIC_64) {
      if (header.cputype == CPU_TYPE_X86_64) {
         if (header.filetype == MH_EXECUTE) {
            os_log(OS_LOG_DEFAULT,
                   "Found x86-64 executable Mach-O file whose header starts at 0x%llx (in task space).",
                   address_in_task_space);

            struct ape_executable_info executable_info = {
               .task_vm_map = task_vm_map,
               .header_address_in_task_space = address_in_task_space,
               .header = header,
               .needs_byte_swap = needs_byte_swap
            };

            status = determine_aslr_offset(task_vm_map, &executable_info);
            if (status != KERN_SUCCESS) {
               os_log_error(OS_LOG_DEFAULT,
                            "determine_aslr_offset failed: %d.",
                            status);
               EXIT_FUNCTION(KERN_FAILURE);
            }

            *is_supported_executable_out = true;
            *executable_info_out = executable_info;
         } else {
            os_log_info(OS_LOG_DEFAULT, "Region does not contain executable Mach-O file; skipping.");
         }
      } else {
         os_log_info(OS_LOG_DEFAULT, "Mach-O file is not for x86-64 platform; skipping.");
      }
   } else {
      os_log_info(OS_LOG_DEFAULT,
                  "Mach-O header magic does not match MH_MAGIC_64: 0x%x; skipping.",
                  header.magic);
   }

   EXIT_FUNCTION(KERN_SUCCESS);
}

static kern_return_t determine_aslr_offset(vm_map_t task_vm_map,
                                           struct ape_executable_info *executable_info_inout) {
   ENTER_FUNCTION();

   mach_vm_address_t address_of_load_commands_in_task_space = executable_info_inout->header_address_in_task_space + sizeof(typeof(executable_info_inout->header));
   uint32_t requested_load_commands_byte_count = executable_info_inout->header.sizeofcmds;

   vm_offset_t load_commands_pointer = 0;
   mach_msg_type_number_t load_commands_byte_count = 0;
   kern_return_t status = mach_vm_read(task_vm_map,
                                       address_of_load_commands_in_task_space,
                                       requested_load_commands_byte_count,
                                       &load_commands_pointer,
                                       &load_commands_byte_count);
   if (status != KERN_SUCCESS) {
      os_log_error(OS_LOG_DEFAULT,
                   "mach_vm_read failed: %d.",
                   status);
      EXIT_FUNCTION(KERN_FAILURE);
   } else if (load_commands_byte_count != requested_load_commands_byte_count) {
      os_log_error(OS_LOG_DEFAULT,
                   "mach_vm_read returned data size (%{iec-bytes}u) that is different from the requested data size (%{iec-bytes}u).",
                   load_commands_byte_count,
                   requested_load_commands_byte_count);
      EXIT_FUNCTION(KERN_FAILURE);
   }

   bool needs_byte_swap = executable_info_inout->needs_byte_swap;

   bool foundNonZeroSegment = false;
   vm_offset_t current_load_commands_offset = 0;
   while (current_load_commands_offset < load_commands_byte_count) {
      os_log_info(OS_LOG_DEFAULT,
                  "Now examining load command at load commands offset 0x%lx.",
                  current_load_commands_offset);

      struct load_command *load_command = (struct load_command *)(load_commands_pointer + current_load_commands_offset);

      struct load_command load_command_local = *load_command;
      if (needs_byte_swap) {
         os_log_info(OS_LOG_DEFAULT,
                     "Swapping bytes in load command struct.");
         swap_load_command(&load_command_local, NXHostByteOrder());
      }

      uint32_t command_type = load_command_local.cmd;
      if (command_type == LC_SEGMENT_64) {
         struct segment_command_64 *segment_command = (struct segment_command_64 *)load_command;
         if (needs_byte_swap) {
            os_log_info(OS_LOG_DEFAULT,
                        "Swapping bytes in segment command struct.");
            swap_segment_command_64(segment_command, NXHostByteOrder());
         }

         if (segment_command->filesize > 0) {
            os_log(OS_LOG_DEFAULT,
                   "Found first segment command that maps file data at load commands offset 0x%lx. This segment is supposed to be where the Mach-O header is located.",
                   current_load_commands_offset);

            mach_vm_offset_t aslr_offset = executable_info_inout->header_address_in_task_space - segment_command->vmaddr;
            os_log(OS_LOG_DEFAULT,
                   "Determined that the ASLR offset for the executable Mach-O file is 0x%llx.",
                   aslr_offset);

            executable_info_inout->aslr_offset = aslr_offset;
            foundNonZeroSegment = true;
            break;
         } else {
            os_log_info(OS_LOG_DEFAULT,
                        "Segment command does not map file data; skipping.");
         }
      } else {
         os_log_info(OS_LOG_DEFAULT,
                     "Load command type is not LC_SEGMENT_64: %u; skipping.",
                     command_type);
      }

      current_load_commands_offset += load_command_local.cmdsize;
   }

   status = mach_vm_deallocate(mach_task_self(),
                               load_commands_pointer,
                               load_commands_byte_count);
   if (status != KERN_SUCCESS) {
      os_log_fault(OS_LOG_DEFAULT,
                   "mach_vm_deallocate failed: %d. Ignoring since it is a relatively small amount of data.",
                   status);
   }

   if (!foundNonZeroSegment) {
      os_log_error(OS_LOG_DEFAULT,
                   "Failed to find a segment command that maps file data.");
      EXIT_FUNCTION(KERN_FAILURE);
   }

   EXIT_FUNCTION(KERN_SUCCESS);
}

NS_ASSUME_NONNULL_END
