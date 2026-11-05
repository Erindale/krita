/*
 *  SPDX-FileCopyrightText: 2026 Krita contributors
 *
 *  SPDX-License-Identifier: GPL-2.0-or-later
 */
#include "KisIosDialogFitter.h"

#include <QApplication>
#include <QEvent>
#include <QLayout>
#include <QScreen>
#include <QWidget>

KisIosDialogFitter::KisIosDialogFitter(QObject *parent)
    : QObject(parent)
{
    if (QScreen *screen = QGuiApplication::primaryScreen()) {
        connect(screen, &QScreen::availableGeometryChanged, this, &KisIosDialogFitter::fitVisibleDialogs);
    }
}

bool KisIosDialogFitter::eventFilter(QObject *watched, QEvent *event)
{
    if (event->type() == QEvent::Show && watched->isWidgetType()) {
        QWidget *widget = static_cast<QWidget *>(watched);
        if (isDialog(widget)) {
            fitToScreen(widget);
        }
    }
    return false;
}

bool KisIosDialogFitter::isDialog(const QWidget *widget)
{
    if (!widget->isWindow()) {
        return false;
    }
    const Qt::WindowType type = widget->windowType();
    return type == Qt::Dialog || type == Qt::Sheet;
}

void KisIosDialogFitter::fitToScreen(QWidget *dialog)
{
    QScreen *screen = dialog->screen();
    if (!screen) {
        return;
    }
    const QRect available = screen->availableGeometry();
    const QRect current = dialog->frameGeometry();
    if (available.contains(current)) {
        return;
    }

    QSize size = current.size();
    if (size.width() > available.width() || size.height() > available.height()) {
        // The layout would otherwise keep the dialog at its minimum size
        if (dialog->layout()) {
            dialog->layout()->setSizeConstraint(QLayout::SetNoConstraint);
        }
        dialog->setMinimumSize(qMin(dialog->minimumWidth(), available.width()),
                               qMin(dialog->minimumHeight(), available.height()));
        size = size.boundedTo(available.size());
    }

    QRect fitted(QPoint(), size);
    fitted.moveCenter(available.center());
    dialog->setGeometry(fitted);
}

void KisIosDialogFitter::fitVisibleDialogs()
{
    const QWidgetList windows = QApplication::topLevelWidgets();
    for (QWidget *window : windows) {
        if (window->isVisible() && isDialog(window)) {
            fitToScreen(window);
        }
    }
}
