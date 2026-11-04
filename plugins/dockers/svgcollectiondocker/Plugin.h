/* This file is part of the KDE project
 * SPDX-FileCopyrightText: 2007 Thomas Zander <zander@kde.org>
 *
 * SPDX-License-Identifier: LGPL-2.0-or-later
 */
#ifndef PLUGIN_H
#define PLUGIN_H

#include <QObject>
#include <QVariantList>

class SvgCollectionDockerPlugin : public QObject
{
    Q_OBJECT

public:
    SvgCollectionDockerPlugin(QObject *parent, const QVariantList &);
    ~SvgCollectionDockerPlugin() override {}
};

#endif
