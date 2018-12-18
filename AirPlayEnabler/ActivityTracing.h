//
//  ActivityTracing.h
//  AirPlayEnabler
//
//  Created by Darren Mo on 2018-12-12.
//  Copyright © 2018 Darren Mo. All rights reserved.
//

@import Foundation;
@import os;

OS_ASSUME_NONNULL_BEGIN

/*!
 * @enum APEOSActivityFlag
 *
 * @discussion
 * Support flags for ape_os_activity_initiate.
 *
 * @constant APEOSActivityFlagDefault
 * Use the default flags.
 *
 * @constant APEOSActivityFlagDetached
 * Detach the newly created activity from the provided activity (if any).  If
 * passed in conjunction with an exiting activity, the activity will only note
 * what activity "created" the new one, but will make the new activity a top
 * level activity.  This allows users to see what activity triggered work
 * without actually relating the activities.
 *
 * @constant APEOSActivityFlagIfNonePresent
 * Will only create a new activity if none present.  If an activity ID is
 * already present, a new object will be returned with the same activity ID
 * underneath.
 *
 * Passing both APEOSActivityFlagDetached and APEOSActivityFlagIfNonePresent
 * is undefined.
 */
typedef NS_OPTIONS(uint32_t, APEOSActivityFlag) {
   APEOSActivityFlagDefault = 0,
   APEOSActivityFlagDetached = 0x1,
   APEOSActivityFlagIfNonePresent = 0x2
};

/*!
 * @function ape_os_activity_initiate
 *
 * @abstract
 * Synchronously initiates an activity using provided block.
 *
 * @discussion
 * Synchronously initiates an activity using the provided block and creates
 * a tracing buffer as appropriate.  All new activities are created as a
 * subactivity of an existing activity on the current thread.
 *
 * <code>
 *     ape_os_activity_initiate("indexing database", APEOSActivityFlagDefault, ^(void) {
 *         // either do work directly or issue work asynchronously
 *     });
 * </code>
 *
 * @param description
 * A constant string describing the activity, e.g., "performClick" or
 * "menuSelection".
 *
 * @param flags
 * Flags to be used when initiating the activity, typically
 * OSActivityFlagDefault.
 *
 * @param activity_block
 * The block to execute a given activity
 */
OS_NOTHROW
void ape_os_activity_initiate(NSString *description,
                              APEOSActivityFlag flags,
                              os_block_t activity_block OS_NOESCAPE NS_SWIFT_NAME(activityBlock)) NS_SWIFT_NAME(OSInitiateActivity(named:flags:activityBlock:));

OS_ASSUME_NONNULL_END
