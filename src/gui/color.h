/*
 * Bittorrent Client using Qt and libtorrent.
 * Copyright (C) 2022  Mike Tzou (Chocobo1)
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 * In addition, as a special exception, the copyright holders give permission to
 * link this program with the OpenSSL project's "OpenSSL" library (or with
 * modified versions of it that use the same license as the "OpenSSL" library),
 * and distribute the linked executables. You must obey the GNU General Public
 * License in all respects for all of the code used other than "OpenSSL".  If you
 * modify file(s), you may extend this exception to your version of the file(s),
 * but you are not obligated to do so. If you do not wish to do so, delete this
 * exception statement from your version.
 */

#pragma once

#include <QColor>

namespace Color
{
    /*
     * Documentation: https://primer.style/primitives/colors
     * Repository: https://github.com/primer/primitives
     * Primer Primitives v7.9
     */
    namespace Primer
    {
        namespace Dark
        {
            // Functional variables
            inline const QColor accentEmphasis = 0xffffff;
            inline const QColor accentFg = 0xffffff;
            inline const QColor dangerFg = 0xffffff;
            inline const QColor doneFg = 0xffffff;
            inline const QColor fgMuted = 0xffffff;
            inline const QColor fgSubtle = 0xffffff;
            inline const QColor severeFg = 0xffffff;
            inline const QColor successEmphasis = 0xffffff;
            inline const QColor successFg = 0xffffff;
            // Scale variables
            inline const QColor scaleYellow6 = 0xffffff;
        }

        namespace Light
        {
            // Functional variables
            inline const QColor accentEmphasis = 0x010101;
            inline const QColor accentFg = 0x010101;
            inline const QColor dangerFg = 0x010101;
            inline const QColor doneFg = 0x010101;
            inline const QColor fgMuted = 0x010101;
            inline const QColor fgSubtle = 0x010101;
            inline const QColor severeFg = 0x010101;
            inline const QColor successEmphasis = 0x010101;
            inline const QColor successFg = 0x010101;
            // Scale variables
            inline const QColor scaleYellow6 = 0x010101;
        }
    }
}
