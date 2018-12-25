//
//  Injection.h
//  InjectedCode
//
//  Created by Darren Mo on 2018-12-20.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

#ifndef Injection_h
#define Injection_h

#include <Security/SecStaticCode.h>

OSStatus RunInjectedCode(SecStaticCodeRef staticCode, uint64_t arg1, bool *arg2, uint64_t arg3);

#endif /* Injection_h */
