# Optimus Player AirPlay Enabler

A helper tool that enables [Optimus Player](https://www.optimusplayer.com/) to stream audio using AirPlay 2.

Update: No longer needed on macOS Catalina or later.

## License

Copyright © 2018–2019 Darren Mo. All rights reserved.

This source code is provided to you for **viewing purposes only**. If you would like additional rights, then send an email to [contact@optimusplayer.com](mailto:contact@optimusplayer.com?subject=AirPlay%20Enabler:%20fill_this_in) describing your use case.

## Background

AirPlay 2 is the second version of the proprietary AirPlay streaming media protocol used by Apple devices. AirPlay 2 focuses on audio, featuring enhanced buffering, stereo pairs, and multi-room audio.

The first version of AirPlay was implemented at the system level, requiring no changes from developers (aside from synchronization with video). However, AirPlay 2 must be integrated at the app level.

On iOS and tvOS, apps use [`AVRoutePickerView`](https://developer.apple.com/documentation/avkit/avroutepickerview) to route audio to AirPlay 2 output devices. This API also exists on macOS (not public yet), but is missing a core component, rendering it unusable.

As of macOS 10.14.6, no apps aside from iTunes have been able to use AirPlay 2. Until now.

## Problem

The core (private) APIs for using AirPlay 2 are inside the `AVFoundation` framework. The `AVFoundation` functions wrap lower-level `CoreMedia` functions (and others).

The complicating piece of the puzzle is an [XPC](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingXPCServices.html#//apple_ref/doc/uid/10000172i-SW6-SW1) service called `AirPlayXPCHelper`. This service simply wraps `CoreMedia` functionality; its main purpose is to use the XPC mechanism to require special privileges from clients who wish to use two key APIs related to AirPlay: discovering output devices and routing to output devices. (The reason for this requirement is unclear to me.)

`AirPlayXPCHelper` requires the `com.apple.avfoundation.allows-access-to-device-list` [entitlement](https://developer.apple.com/documentation/bundleresources/entitlements) to discover output devices and the `com.apple.avfoundation.allows-set-output-device` entitlement to route to output devices. Only Apple-provisioned executables can have these restricted entitlements. This is the problem that the helper tool addresses.

## Design

### Overview

Restricted entitlements are validated by the `amfid` system process when an executable is launched. The helper tool injects code into `amfid` to bypass this validation when launching Optimus Player executables, thus allowing Optimus Player executables to obtain the privileges needed to use the AirPlay 2 private APIs.

### Goals

- To enable Optimus Player to use AirPlay 2.
- To minimize side effects on the system and on other apps.
- To be low-maintenance.
- To be easily removable.

### Specific Requirements

- The helper tool should be able to inject code into the `amfid` system process.
- The code injection should only proceed if the relevant sections of the original `amfid` code are exactly as expected. (The `amfid` code may change due to operating system updates.)
- The injection of code should be as atomic as possible; if an operation fails, the injector should roll back previous operations.
- The injected code should only bypass the restricted entitlements validation for Optimus Player executables; other executables should still be validated normally.
- The helper tool should run automatically, requiring no action from the user after installation (aside from updates to the helper tool).
- The code injection should be removed automatically during uninstallation.

### Solution

#### Privileged Helper Tool

The helper tool is implemented as a [Launch Daemon](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/DesigningDaemons.html#//apple_ref/doc/uid/10000172i-SW4-SW5), which gives it the following features:

- runs with `root` user permissions, which is needed to inject code into the `amfid` system process;
- launches automatically at system startup;
- re-launches when killed; and
- integrates with XPC.

When the helper tool is launched, it first runs the code injector and then starts the XPC service.

#### XPC Service

One component of the helper tool is the XPC service. The XPC service allows Optimus Player to get the version of the helper tool to check for updates and to uninstall the helper tool.

The uninstallation is performed by the helper tool itself (which is already running with `root` user permissions) to avoid an unnecessary authorization request.

The helper tool only allows requests from Optimus Player executables.

#### Code Injector

The code injector modifies the running `amfid` process but does not modify the file system. This approach is required because the `amfid` executable must have a valid Apple code signature in order to be launched.

The code injector first finds the `amfid` process and then analyzes its memory structure to find the memory location of the executable image. Once the executable image has been found, code can be injected into the executable.

The procedure for injecting code:

1. Get the patches (“patch” described below) that are compatible with the current operating system version.
2. Suspend the `amfid` process to prevent the memory from changing. (The memory can still change if there is another code injector running at the same time, but there is nothing we can do about that.)
3. Apply the patches.
4. If a patch fails to be applied, roll back the already-applied patches.

A patch consists mainly of the following properties:

- address in the executable
- requirements
  - address in the executable
  - required data
- target data
- replacement data

(There are some extra details for handling external symbols and other problems; read the code if you wish to learn more.)

The procedure for removing the code injection is similar.

#### Injected Code

There is a function in the original `amfid` code that checks whether an executable is allowed to have restricted entitlements. The helper tool replaces the call to that function with a call to an injected function.

The injected function checks whether the executable being evaluated is an Optimus Player executable. If it is, then the injected function returns a status value indicating success. If the executable is not an Optimus Player executable or if an error occurred while checking, then the injected function calls the original function and returns its status value.
