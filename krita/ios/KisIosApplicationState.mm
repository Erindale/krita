/*
 *  SPDX-FileCopyrightText: 2026 Krita contributors
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "KisIosApplicationState.h"

#import <UIKit/UIKit.h>

void kisIosRunWhenApplicationActive(std::function<void()> callback)
{
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        callback();
        return;
    }

    __block id observer = nil;
    observer = [NSNotificationCenter.defaultCenter
        addObserverForName:UIApplicationDidBecomeActiveNotification
                    object:nil
                     queue:NSOperationQueue.mainQueue
                usingBlock:^(NSNotification *) {
                    [NSNotificationCenter.defaultCenter removeObserver:observer];
                    observer = nil;
                    callback();
                }];
}
