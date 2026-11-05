/*
 *  SPDX-FileCopyrightText: 2026 Krita contributors
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "KisIosKeyboardPolicy.h"

#include <QAbstractSpinBox>
#include <QApplication>
#include <QComboBox>
#include <QMouseEvent>
#include <QInputMethod>
#include <QInputMethodQueryEvent>
#include <QLineEdit>
#include <QPlainTextEdit>
#include <QTextEdit>
#include <QWidget>

KisIosKeyboardPolicy::KisIosKeyboardPolicy(QObject *parent)
    : QObject(parent)
{
}

bool KisIosKeyboardPolicy::isTextEntry(const QWidget *widget)
{
    if (const QLineEdit *lineEdit = qobject_cast<const QLineEdit *>(widget)) {
        // the editor inside a spin box is not a text field for this purpose
        return !lineEdit->isReadOnly() && !qobject_cast<QAbstractSpinBox *>(lineEdit->parentWidget());
    }
    if (const QTextEdit *textEdit = qobject_cast<const QTextEdit *>(widget)) {
        return !textEdit->isReadOnly();
    }
    if (const QPlainTextEdit *plainTextEdit = qobject_cast<const QPlainTextEdit *>(widget)) {
        return !plainTextEdit->isReadOnly();
    }
    return false;
}

bool KisIosKeyboardPolicy::isUnlocked(const QWidget *widget) const
{
    // the tapped widget may be the editor of the focus object (an editable
    // combo box) or the other way round
    return m_unlocked
        && (widget == m_unlocked || widget->isAncestorOf(m_unlocked) || m_unlocked->isAncestorOf(widget));
}

QAbstractSpinBox *KisIosKeyboardPolicy::editableSpinBoxAt(QWidget *widget)
{
    for (QWidget *w = widget; w; w = w->parentWidget()) {
        if (QAbstractSpinBox *spinBox = qobject_cast<QAbstractSpinBox *>(w)) {
            return spinBox->isReadOnly() ? nullptr : spinBox;
        }
        if (w->isWindow()) {
            break;
        }
    }
    return nullptr;
}

void KisIosKeyboardPolicy::unlockAndShow(QWidget *widget)
{
    m_unlocked = widget;
    if (widget->hasFocus()) {
        // already focused but held back: bring the keyboard up now
        QGuiApplication::inputMethod()->update(Qt::ImEnabled);
        QGuiApplication::inputMethod()->show();
    }
}

bool KisIosKeyboardPolicy::eventFilter(QObject *watched, QEvent *event)
{
    if (!watched->isWidgetType()) {
        return false;
    }
    QWidget *widget = static_cast<QWidget *>(watched);

    switch (event->type()) {
    case QEvent::MouseButtonPress:
        // touches arrive as mouse events; a press on a text field unlocks it
        // before it gets focus, so the keyboard comes up for that tap
        if (isTextEntry(widget)) {
            unlockAndShow(widget);
        }
        // a number field only unlocks on release, and only for a tap: a
        // drag on a slider spin box changes the value instead
        if (!m_pressedSpinBox) {
            m_pressedSpinBox = editableSpinBoxAt(widget);
            m_pressPosition = static_cast<QMouseEvent *>(event)->globalPosition();
        }
        break;
    case QEvent::MouseButtonRelease:
        if (m_pressedSpinBox) {
            QAbstractSpinBox *spinBox = m_pressedSpinBox;
            m_pressedSpinBox = nullptr;
            const QPointF moved = static_cast<QMouseEvent *>(event)->globalPosition() - m_pressPosition;
            if (moved.manhattanLength() < 12 && spinBox->isEnabled()) {
                unlockAndShow(spinBox);
            }
        }
        break;
    case QEvent::FocusOut:
        if (widget == m_unlocked) {
            m_unlocked = nullptr;
        }
        break;
    case QEvent::InputMethodQuery: {
        QInputMethodQueryEvent *query = static_cast<QInputMethodQueryEvent *>(event);
        if (!(query->queries() & Qt::ImEnabled) || isUnlocked(widget)) {
            break;
        }
        // Qt shows a dropdown's list as a native picker in the keyboard's
        // place (QIOSMenu answers this query through its own event filter);
        // a non-editable combo box never asks for a keyboard otherwise
        if (QComboBox *comboBox = qobject_cast<QComboBox *>(widget); comboBox && !comboBox->isEditable()) {
            break;
        }
        // let the widget answer, then hold the keyboard back
        watched->event(event);
        query->setValue(Qt::ImEnabled, false);
        if (query->queries() & Qt::ImReadOnly) {
            query->setValue(Qt::ImReadOnly, false);
        }
        return true;
    }
    default:
        break;
    }
    return false;
}
