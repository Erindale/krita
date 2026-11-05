/*
 *  SPDX-FileCopyrightText: 2026 Krita contributors
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */
#ifndef KIS_IOS_KEYBOARD_POLICY_H
#define KIS_IOS_KEYBOARD_POLICY_H

#include <QObject>
#include <QPointF>
#include <QPointer>

class QAbstractSpinBox;
class QWidget;

/**
 * "Tap to type" for iPadOS.
 *
 * Qt for iOS shows the on-screen keyboard (or, with a hardware keyboard,
 * the suggestion bar) whenever the focused widget accepts text input, and
 * scrolls the window up to keep it visible. Krita moves focus into search
 * fields and spin boxes all the time (popups, dialogs, sliders), so the
 * keyboard kept appearing while painting.
 *
 * Installed as an application event filter, this answers "not enabled" to
 * the platform's input method query (Qt::ImEnabled) for every focus object
 * except a text field the user tapped. A tap on a text field unlocks it
 * before focus moves there, so the keyboard comes up as usual; focus that
 * arrives any other way (a popup or dialog opening, a spin box or slider
 * being dragged) leaves the keyboard down. A tap (not a drag) on a number
 * field unlocks it too. Non-editable dropdowns are left alone, since Qt
 * shows their list as a native picker in the keyboard's place.
 */
class KisIosKeyboardPolicy : public QObject
{
    Q_OBJECT
public:
    explicit KisIosKeyboardPolicy(QObject *parent = nullptr);

    bool eventFilter(QObject *watched, QEvent *event) override;

private:
    static bool isTextEntry(const QWidget *widget);
    static QAbstractSpinBox *editableSpinBoxAt(QWidget *widget);
    bool isUnlocked(const QWidget *widget) const;
    void unlockAndShow(QWidget *widget);

    QPointer<QWidget> m_unlocked;
    QPointer<QAbstractSpinBox> m_pressedSpinBox;
    QPointF m_pressPosition;
};

#endif
