/*
 *  SPDX-FileCopyrightText: 2026 Krita contributors
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */
#ifndef KIS_IOS_APPLICATION_STATE_H
#define KIS_IOS_APPLICATION_STATE_H

#include <functional>

/**
 * Runs @p callback from Qt's event loop once UIKit reports the application
 * active: right away if it already is, otherwise after
 * UIApplicationDidBecomeActiveNotification.
 *
 * Qt reports Qt::ApplicationActive when the window scene activates, which
 * on iPadOS can be over a second before UIApplication itself is active;
 * until then iOS refuses GL calls, so windows shown in that gap stay black.
 */
void kisIosRunWhenApplicationActive(std::function<void()> callback);

#endif
