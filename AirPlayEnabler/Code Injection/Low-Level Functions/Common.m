//
//  Common.m
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-23.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

#import "Common.h"

NS_ASSUME_NONNULL_BEGIN

kern_return_t ape_create_cstring(vm_map_t task_vm_map,
                                 mach_vm_address_t address_in_task_space,
                                 const char **cstring_out) {
   ENTER_FUNCTION();

   if (cstring_out == NULL) {
      os_log_error(OS_LOG_DEFAULT, "cstring_out should not be NULL.");
      EXIT_FUNCTION(KERN_INVALID_ARGUMENT);
   }
   *cstring_out = NULL;

   mach_vm_size_t cstring_byte_count = 1;
   char *cstring = malloc(cstring_byte_count);
   if (cstring == NULL) {
      EXIT_FUNCTION(KERN_NO_SPACE);
   }

   // 128 was chosen by eyeballing the system framework names.
   // The longest file path seems to be 122 bytes: /System/Library/PrivateFrameworks/SpeechRecognitionCommandServices.framework/Versions/A/SpeechRecognitionCommandServices.
   mach_vm_size_t buffer_size = 128;
   char buffer[buffer_size];

   mach_vm_address_t current_address_in_task_space = address_in_task_space;
   mach_vm_size_t max_bytes_to_read = buffer_size;
   while (true) {
      mach_vm_size_t bytes_read = 0;
      kern_return_t status = mach_vm_read_overwrite(task_vm_map,
                                                    current_address_in_task_space,
                                                    max_bytes_to_read,
                                                    (mach_vm_address_t)buffer,
                                                    &bytes_read);
      if (status == KERN_INVALID_ADDRESS) {
         max_bytes_to_read -= 1;
         if (max_bytes_to_read == 0) {
            break;
         }
      } else if (status != KERN_SUCCESS) {
         os_log_error(OS_LOG_DEFAULT,
                      "mach_vm_read_overwrite failed: %d.",
                      status);
         goto failure;
      } else if (bytes_read != max_bytes_to_read) {
         os_log_error(OS_LOG_DEFAULT,
                      "mach_vm_read_overwrite returned size (%{iec-bytes}llu) that is different from the requested size (%{iec-bytes}llu).",
                      bytes_read,
                      max_bytes_to_read);
         goto failure;
      }

      bool did_find_null_terminator = false;
      mach_vm_size_t bytes_to_copy = 0;
      for (mach_vm_size_t idx = 0; idx < bytes_read; idx++) {
         if (buffer[idx] == '\0') {
            did_find_null_terminator = true;
            break;
         }

         bytes_to_copy += 1;
      }

      if (bytes_to_copy > 0) {
         mach_vm_size_t new_cstring_byte_count = cstring_byte_count + bytes_to_copy;

         char *new_cstring = realloc(cstring, new_cstring_byte_count);
         if (new_cstring == NULL) {
            free(cstring);
            EXIT_FUNCTION(KERN_NO_SPACE);
         }
         cstring = new_cstring;

         memcpy(cstring + cstring_byte_count - 1, buffer, bytes_to_copy);

         cstring_byte_count = new_cstring_byte_count;
      }

      if (did_find_null_terminator) {
         break;
      }

      current_address_in_task_space += bytes_read;
   }

   cstring[cstring_byte_count - 1] = '\0';
   *cstring_out = cstring;

   EXIT_FUNCTION(KERN_SUCCESS);

failure:
   free(cstring);
   EXIT_FUNCTION(KERN_FAILURE);
}

NS_ASSUME_NONNULL_END
