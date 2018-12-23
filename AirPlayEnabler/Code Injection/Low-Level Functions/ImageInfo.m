//
//  ImageInfo.m
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-23.
//  Copyright © 2018 Darren Mo. All rights reserved.
//
//  Inspired by rodionovd: https://github.com/rodionovd/liblorgnette/blob/master/lorgnette.c
//

#import "ImageInfo.h"

@import MachO;
@import os.log;

#import "Common.h"

NS_ASSUME_NONNULL_BEGIN

// MARK: - Structs

// Compatible with the 64-bit version of the dyld_all_image_infos struct.
struct ape_dyld_all_image_infos {
   uint32_t version;

   uint32_t image_info_count;
   mach_vm_address_t image_infos_address_in_task_space;

   // Unused fields are omitted.
};

// Compatible with the 64-bit version of the dyld_image_info struct.
struct ape_dyld_image_info {
   mach_vm_address_t header_address_in_task_space;
   mach_vm_address_t file_path_address_in_task_space;

   // Unused fields are omitted.
};

// MARK: - Static Function Declarations

static bool dyld_needs_swap(uint32_t dyld_all_image_infos_version);
static void swap_dyld_all_image_infos(struct ape_dyld_all_image_infos *dyld_all_image_infos_inout);
static void swap_dyld_image_info(struct ape_dyld_image_info *dyld_image_info_inout);

// MARK: - Function Definitions

kern_return_t ape_find_image_info(vm_map_t task_vm_map,
                                  mach_vm_address_t dyld_all_image_infos_address_in_task_space,
                                  const char *image_file_path,
                                  struct ape_image_info *image_info_out) {
   ENTER_FUNCTION();

   if (image_file_path == NULL) {
      os_log_error(OS_LOG_DEFAULT, "image_file_path should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }
   if (image_info_out == NULL) {
      os_log_error(OS_LOG_DEFAULT, "image_info_out should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }

   struct ape_dyld_all_image_infos dyld_all_image_infos = {0};
   mach_vm_size_t requested_dyld_all_image_infos_size = sizeof(dyld_all_image_infos);
   mach_vm_size_t dyld_all_image_infos_size = 0;
   kern_return_t status = mach_vm_read_overwrite(task_vm_map,
                                                 dyld_all_image_infos_address_in_task_space,
                                                 requested_dyld_all_image_infos_size,
                                                 (mach_vm_address_t)&dyld_all_image_infos,
                                                 &dyld_all_image_infos_size);
   if (status != KERN_SUCCESS) {
      os_log_error(OS_LOG_DEFAULT,
                   "mach_vm_read_overwrite failed: %d.",
                   status);
      EXIT_FUNCTION(KERN_FAILURE);
   } else if (dyld_all_image_infos_size != requested_dyld_all_image_infos_size) {
      os_log_error(OS_LOG_DEFAULT,
                   "mach_vm_read_overwrite returned size (%{iec-bytes}llu) that is different from the requested size (%{iec-bytes}llu).",
                   dyld_all_image_infos_size,
                   requested_dyld_all_image_infos_size);
      EXIT_FUNCTION(KERN_FAILURE);
   }

   bool needs_swap = dyld_needs_swap(dyld_all_image_infos.version);
   if (needs_swap) {
      swap_dyld_all_image_infos(&dyld_all_image_infos);
   }

   uint32_t image_info_count = dyld_all_image_infos.image_info_count;
   mach_vm_address_t current_address_in_task_space = dyld_all_image_infos.image_infos_address_in_task_space;
   for (uint32_t idx = 0; idx < image_info_count; idx++) {
      struct ape_dyld_image_info dyld_image_info = {0};
      mach_vm_size_t requested_dyld_image_info_size = sizeof(dyld_image_info);
      mach_vm_size_t dyld_image_info_size = 0;
      kern_return_t status = mach_vm_read_overwrite(task_vm_map,
                                                    current_address_in_task_space,
                                                    requested_dyld_image_info_size,
                                                    (mach_vm_address_t)&dyld_image_info,
                                                    &dyld_image_info_size);
      if (status != KERN_SUCCESS) {
         os_log_error(OS_LOG_DEFAULT,
                      "mach_vm_read_overwrite failed: %d.",
                      status);
         EXIT_FUNCTION(KERN_FAILURE);
      } else if (dyld_image_info_size != requested_dyld_image_info_size) {
         os_log_error(OS_LOG_DEFAULT,
                      "mach_vm_read_overwrite returned size (%{iec-bytes}llu) that is different from the requested size (%{iec-bytes}llu).",
                      dyld_image_info_size,
                      requested_dyld_image_info_size);
         EXIT_FUNCTION(KERN_FAILURE);
      }

      if (needs_swap) {
         swap_dyld_image_info(&dyld_image_info);
      }

      const char *image_file_path_from_dyld = NULL;
      status = ape_create_cstring(task_vm_map,
                                  dyld_image_info.file_path_address_in_task_space,
                                  &image_file_path_from_dyld);
      if (status != KERN_SUCCESS) {
         os_log_error(OS_LOG_DEFAULT,
                      "ape_create_cstring failed: %d.",
                      status);
         EXIT_FUNCTION(KERN_FAILURE);
      }

      int compare_result = strcmp(image_file_path_from_dyld, image_file_path);
      free((void *)image_file_path_from_dyld);

      if (compare_result == 0) {
         os_log(OS_LOG_DEFAULT,
                "Found image for `%{public}s` at 0x%llx (in task space).",
                image_file_path_from_dyld,
                dyld_image_info.header_address_in_task_space);

         struct ape_image_info image_info = {
            .header_address_in_task_space = dyld_image_info.header_address_in_task_space
         };
         *image_info_out = image_info;

         break;
      }

      // ape_dyld_image_info is only a subset of dyld_image_info, so we need to use
      // the size of the latter struct to advance the address.
      current_address_in_task_space += sizeof(struct dyld_image_info);
   }

   EXIT_FUNCTION(KERN_SUCCESS);
}

static bool dyld_needs_swap(uint32_t dyld_all_image_infos_version) {
   // From the LLVM source code:
   // > If anything in the high byte is set, we probably got the byte order incorrect.
   if ((dyld_all_image_infos_version & 0xff000000) != 0) {
      return true;
   }

   return false;
}

static void swap_dyld_all_image_infos(struct ape_dyld_all_image_infos *dyld_all_image_infos_inout) {
   dyld_all_image_infos_inout->version = _OSSwapInt32(dyld_all_image_infos_inout->version);
   dyld_all_image_infos_inout->image_info_count = _OSSwapInt32(dyld_all_image_infos_inout->image_info_count);
   dyld_all_image_infos_inout->image_infos_address_in_task_space = _OSSwapInt64(dyld_all_image_infos_inout->image_infos_address_in_task_space);
}

static void swap_dyld_image_info(struct ape_dyld_image_info *dyld_image_info_inout) {
   dyld_image_info_inout->header_address_in_task_space = _OSSwapInt64(dyld_image_info_inout->header_address_in_task_space);
   dyld_image_info_inout->file_path_address_in_task_space = _OSSwapInt64(dyld_image_info_inout->file_path_address_in_task_space);
}

NS_ASSUME_NONNULL_END
