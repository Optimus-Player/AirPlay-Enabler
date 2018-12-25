//
//  Injection.c
//  InjectedCode
//
//  Created by Darren Mo on 2018-12-20.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

#include "Injection.h"

#include <CoreFoundation/CoreFoundation.h>
#include <Security/SecRequirement.h>
#include <dispatch/once.h>
#include <os/log.h>

__attribute__((__optnone__))
OSStatus OriginalFunction(SecStaticCodeRef staticCode, uint64_t arg1, bool *arg2, uint64_t arg3) {
   return errSecSuccess;
}

OSStatus RunInjectedCode(SecStaticCodeRef staticCode, uint64_t arg1, bool *arg2, uint64_t arg3) {
   static os_log_t log = NULL;
   static dispatch_once_t onceToken;
   dispatch_once(&onceToken, ^{
      log = os_log_create("mo.darren.optimus.player.mac.airplay-enabler", "Injected Code");
   });

   os_log(log, "Starting to run injected code.");

   OSStatus status = errSecSuccess;

   CFStringRef requirementText = CFSTR("anchor apple generic and (certificate leaf[field.1.2.840.113635.100.6.1.9] or certificate 1[field.1.2.840.113635.100.6.2.6] and certificate leaf[field.1.2.840.113635.100.6.1.13] and certificate leaf[subject.OU] = PVLQ49LAH3)");

   SecRequirementRef requirement = NULL;
   status = SecRequirementCreateWithString(requirementText,
                                           kSecCSDefaultFlags,
                                           &requirement);
   if (status != errSecSuccess) {
      os_log_error(log,
                   "Failed to create requirement: %d.",
                   status);
      goto originalCode;
   }

   status = SecStaticCodeCheckValidityWithErrors(staticCode,
                                                 kSecCSDefaultFlags,
                                                 requirement,
                                                 NULL);
   CFRelease(requirement);
   if (status == errSecCSReqFailed) {
      os_log(log, "Code does not meet requirement.");
      goto originalCode;
   } else if (status != errSecSuccess) {
      os_log_error(log,
                   "Failed to check whether code meets requirement: %d.",
                   status);
      goto originalCode;
   }

   status = errSecSuccess;
   goto exit;

originalCode:
   status = OriginalFunction(staticCode, arg1, arg2, arg3);

exit:
   os_log(log, "Finished running injected code.");
   return status;
}
