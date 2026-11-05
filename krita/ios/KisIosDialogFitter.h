/*
 *  SPDX-FileCopyrightText: 2026 Krita contributors
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */
#ifndef KIS_IOS_DIALOG_FITTER_H
#define KIS_IOS_DIALOG_FITTER_H

#include <QObject>

class QWidget;

/**
 * Keeps dialogs on screen on iPadOS.
 *
 * iOS has no window manager: a dialog is shown at whatever size its layout
 * asks for, and on a small iPad (the iPad mini is 744 points wide) that can
 * put its buttons off screen with no way to move it. Installed as an
 * application event filter, this fits every dialog that is larger than the
 * screen's available area when it is shown (or when the screen rotates),
 * relaxing the layout's minimum size if it has to, and centres it.
 * Dialogs that fit are left alone.
 */
class KisIosDialogFitter : public QObject
{
    Q_OBJECT
public:
    explicit KisIosDialogFitter(QObject *parent = nullptr);

    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    static bool isDialog(const QWidget *widget);
    static void fitToScreen(QWidget *dialog);
    void fitVisibleDialogs();
};

#endif
