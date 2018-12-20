//
//  ActivityTracing.m
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-12.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

#import "ActivityTracing.h"

@import os.activity;
@import os.lock;

OS_ASSUME_NONNULL_BEGIN

static const char *PermanentCStringFromNSString(NSString *nsString);

void ape_os_activity_initiate(NSString *description,
                              APEOSActivityFlag flags,
                              os_block_t activity_block OS_NOESCAPE) {
   _os_activity_initiate(&__dso_handle,
                         PermanentCStringFromNSString(description),
                         (os_activity_flag_t)flags,
                         activity_block);
}

static const char *PermanentCStringFromNSString(NSString *nsString) {
   static os_unfair_lock lock = OS_UNFAIR_LOCK_INIT;
   os_unfair_lock_lock(&lock);

   static NSMapTable<NSString *, id> *nsStringToCStringMap = nil;
   if (nsStringToCStringMap == nil) {
      nsStringToCStringMap = [[NSMapTable alloc] initWithKeyOptions:(NSPointerFunctionsStrongMemory | NSPointerFunctionsObjectPersonality)
                                                       valueOptions:(NSPointerFunctionsMallocMemory | NSPointerFunctionsCStringPersonality | NSPointerFunctionsCopyIn)
                                                           capacity:1];
   }

   const char *cString = (__bridge void *)[nsStringToCStringMap objectForKey:nsString];
   if (cString == NULL) {
      [nsStringToCStringMap setObject:(__bridge id)(void *)nsString.UTF8String forKey:[nsString copy]];
      cString = (__bridge void *)[nsStringToCStringMap objectForKey:nsString];
   }

   os_unfair_lock_unlock(&lock);

   return cString;
}

OS_ASSUME_NONNULL_END
