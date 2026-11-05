/*
 *  SPDX-FileCopyrightText: 2026 Krita contributors
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "KisIosApplicationState.h"

#include <QCoreApplication>
#include <QMetaObject>

#import <UIKit/UIKit.h>

namespace {
// Run the callback from Qt's event loop, not from inside the UIKit callout:
// start-up may open modal dialogs (autosave recovery), and UIKit cannot
// finish activating the scene, or draw anything, until the notification
// handler returns.
void runQueued(std::function<void()> callback)
{
    QMetaObject::invokeMethod(QCoreApplication::instance(), [callback]() { callback(); }, Qt::QueuedConnection);
}
}

void kisIosRunWhenApplicationActive(std::function<void()> callback)
{
    if (UIApplication.sharedApplication.applicationState == UIApplicationStateActive) {
        runQueued(callback);
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
                    runQueued(callback);
                }];
}
