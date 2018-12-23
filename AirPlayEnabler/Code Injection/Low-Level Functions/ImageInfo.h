//
//  ImageInfo.h
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-23.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

@import Darwin;
@import Foundation;

NS_ASSUME_NONNULL_BEGIN

struct ape_image_info {
   mach_vm_address_t header_address_in_task_space;
};

kern_return_t ape_image_info_find(vm_map_t task_vm_map,
                                  mach_vm_address_t dyld_all_image_infos_address_in_task_space,
                                  const char *image_file_path,
                                  struct ape_image_info *image_info_out);

NS_ASSUME_NONNULL_END
