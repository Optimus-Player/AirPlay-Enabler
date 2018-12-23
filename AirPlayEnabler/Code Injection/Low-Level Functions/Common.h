//
//  Common.h
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-23.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

@import Darwin;
@import Foundation;
@import os.log;

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

NS_ASSUME_NONNULL_BEGIN

kern_return_t ape_create_cstring(vm_map_t task_vm_map,
                                 mach_vm_address_t address_in_task_space,
                                 const char **cstring_out);

NS_ASSUME_NONNULL_END
