//
//  AirPlayEnablerInterface.swift
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-18.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

import Foundation

@objc
public protocol AirPlayEnablerInterface {
   /**
    Checks whether the privileged helper is running.

    - Parameter reply: The XPC reply block. A call to this block indicates that the
                       privileged helper is running.
    */
   func isPrivilegedHelperRunning(withReply reply: @escaping () -> Void)

   /**
    Gets the privileged helper version.

    - Parameter reply: The XPC reply block.
    - Parameter version: The privileged helper version.
    */
   func getPrivilegedHelperVersion(withReply reply: @escaping (_ version: PrivilegedHelperVersion) -> Void)

   /**
    Deletes the privileged helper files, unregisters the privileged helper in launchd,
    and terminates the running process.

    After calling this function, wait for a connection interruption and then call
    `isPrivilegedHelperRunning(withReply:)` to confirm that the privileged helper has
    indeed been terminated.

    - Parameter reply: The XPC reply block. This will only be called if an error occurred;
                       success means the privileged helper process has been terminated.
    - Parameter nsError: The error that occurred. Convert the error using
                         `UninstallPrivilegedHelperError.init(nsError:)`.
    */
   func uninstallPrivilegedHelper(withReply reply: @escaping (_ nsError: NSError) -> Void)
}

public enum UninstallPrivilegedHelperError: Int, AirPlayEnablerInterfaceError {
   public static let errorDomain: NSErrorDomain = "mo.darren.optimus.player.mac.airplay-enabler.uninstallPrivilegedHelper"

   case failedToReadLaunchdPlist
   case failedToDecodeLaunchdPlist
   case unsupportedLaunchdPlistProgramArguments
   case failedToFindProgramPathInLaunchdPlist
   case failedToDeleteLaunchdPlist
   case failedToDeleteProgram
   case failedToRemoveCodeInjection
   case failedToRunLaunchctlProcess
   case launchctlFailed
   case timedOutWaitingForLaunchdToKillPrivilegedHelper
}
