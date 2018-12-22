//
//  TaskVM.m
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-12.
//  Copyright © 2018 Darren Mo. All rights reserved.
//
//  Inspired by fG!: https://sourceforge.net/p/machoview/code/ci/master/tree/Attach.mm
//

#import "TaskVM.h"

@import os.log;

// MARK: - Macros

#define ENTER_FUNCTION() {                                      \
   os_log_debug(OS_LOG_DEFAULT, "Entering %s.", __FUNCTION__);  \
}

#define EXIT_FUNCTION(return_value) {                \
   os_log_debug(OS_LOG_DEFAULT,                      \
                "Exiting %s with return value %d.",  \
                __FUNCTION__,                        \
                (return_value));                     \
   return (return_value);                            \
}

// MARK: - Static Function Declarations

static kern_return_t read_executable_header_at_address(vm_map_t task_vm_map,
                                                       mach_vm_address_t address_in_task_space,
                                                       bool *is_supported_executable_out,
                                                       struct ape_executable_header_context *executable_header_context_out);
static kern_return_t determine_aslr_offset(vm_map_t task_vm_map,
                                           struct ape_executable_header_context *executable_header_context_inout);

// MARK: - Function Definitions

kern_return_t ape_read_executable_header(vm_map_t task_vm_map,
                                         struct ape_executable_header_context *executable_header_context_out) {
   ENTER_FUNCTION();

   if (executable_header_context_out == NULL) {
      os_log_error(OS_LOG_DEFAULT, "executable_header_context_out should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }

   mach_vm_address_t current_address_in_task_space = 0;
   for (unsigned long iteration_counter = 0;; iteration_counter++) {
      os_log_info(OS_LOG_DEFAULT,
                  "Starting region iteration %lu. current_address_in_task_space = 0x%llx.",
                  iteration_counter,
                  current_address_in_task_space);

      mach_vm_size_t region_size = 0;
      natural_t nesting_depth = UINT_MAX;
      struct vm_region_submap_info_64 submap_info = {0};
      mach_msg_type_number_t info_count = VM_REGION_SUBMAP_INFO_COUNT_64;

      kern_return_t status = mach_vm_region_recurse(task_vm_map,
                                                    &current_address_in_task_space,
                                                    &region_size,
                                                    &nesting_depth,
                                                    (vm_region_recurse_info_t)&submap_info,
                                                    &info_count);
      if (status != KERN_SUCCESS) {
         os_log_error(OS_LOG_DEFAULT,
                      "mach_vm_region_recurse failed: %d.",
                      status);
         EXIT_FUNCTION(KERN_FAILURE);
      } else if (submap_info.is_submap) {
         os_log_fault(OS_LOG_DEFAULT,
                      "mach_vm_region_recurse returned submap even though we specified a nesting depth of %u.",
                      nesting_depth);
         EXIT_FUNCTION(KERN_FAILURE);
      }

      if ((submap_info.protection & VM_PROT_EXECUTE) != 0) {
         mach_vm_size_t header_size = sizeof(typeof(executable_header_context_out->header));
         if (region_size >= header_size) {
            bool is_supported_executable = false;
            status = read_executable_header_at_address(task_vm_map,
                                                       current_address_in_task_space,
                                                       &is_supported_executable,
                                                       executable_header_context_out);
            if (status != KERN_SUCCESS) {
               os_log_error(OS_LOG_DEFAULT,
                            "read_executable_header_at_address failed: %d.",
                            status);
               EXIT_FUNCTION(KERN_FAILURE);
            }

            if (is_supported_executable) {
               break;
            }
         } else {
            os_log_info(OS_LOG_DEFAULT,
                        "Region is not large enough to contain a Mach-O header; skipping.");
         }
      } else {
         os_log_info(OS_LOG_DEFAULT,
                     "Region does not have execute permission; skipping.");
      }

      current_address_in_task_space += region_size;
   }

   EXIT_FUNCTION(KERN_SUCCESS);
}

static kern_return_t read_executable_header_at_address(vm_map_t task_vm_map,
                                                       mach_vm_address_t address_in_task_space,
                                                       bool *is_supported_executable_out,
                                                       struct ape_executable_header_context *executable_header_context_out) {
   ENTER_FUNCTION();

   if (is_supported_executable_out == NULL) {
      os_log_error(OS_LOG_DEFAULT, "is_supported_executable_out should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }
   if (executable_header_context_out == NULL) {
      os_log_error(OS_LOG_DEFAULT, "executable_header_context_out should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }

   typeof(executable_header_context_out->header) header = {0};
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
                   "mach_vm_read_overwrite returned header size (%{iec-bytes}llu) that is different from the requested header size (%{iec-bytes}llu).",
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
                   "Found region with x86-64 executable Mach-O file whose header starts at 0x%llx (in task space).",
                   address_in_task_space);

            struct ape_executable_header_context executable_header_context = {
               .task_vm_map = task_vm_map,
               .header_address_in_task_space = address_in_task_space,
               .header = header,
               .needs_byte_swap = needs_byte_swap
            };

            status = determine_aslr_offset(task_vm_map, &executable_header_context);
            if (status != KERN_SUCCESS) {
               os_log_error(OS_LOG_DEFAULT,
                            "determine_aslr_offset failed: %d.",
                            status);
               EXIT_FUNCTION(KERN_FAILURE);
            }

            *is_supported_executable_out = true;
            *executable_header_context_out = executable_header_context;
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
                                           struct ape_executable_header_context *executable_header_context_inout) {
   ENTER_FUNCTION();

   if (executable_header_context_inout == NULL) {
      os_log_error(OS_LOG_DEFAULT, "executable_header_context_inout should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }

   mach_vm_address_t address_of_load_commands_in_task_space = executable_header_context_inout->header_address_in_task_space + sizeof(typeof(executable_header_context_inout->header));
   uint32_t requested_load_commands_byte_count = executable_header_context_inout->header.sizeofcmds;

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

   bool needs_byte_swap = executable_header_context_inout->needs_byte_swap;

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

            mach_vm_offset_t aslr_offset = executable_header_context_inout->header_address_in_task_space - segment_command->vmaddr;
            os_log(OS_LOG_DEFAULT,
                   "Determined that the ASLR offset for the executable Mach-O file is 0x%llx.",
                   aslr_offset);

            executable_header_context_inout->aslr_offset = aslr_offset;
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
