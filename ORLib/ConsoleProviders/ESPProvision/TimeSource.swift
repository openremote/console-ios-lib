/*
 * Copyright 2025, OpenRemote Inc.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as
 * published by the Free Software Foundation, either version 3 of the
 * License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program. If not, see <https://www.gnu.org/licenses/>.
 *
 * SPDX-License-Identifier: AGPL-3.0-or-later
 */

import Foundation
import Darwin

protocol TimeSource {
    var now: TimeInterval { get }
}

struct SystemTimeSource: TimeSource {
    private static let timebaseInfo: mach_timebase_info_data_t = {
        var timebaseInfo = mach_timebase_info_data_t()
        mach_timebase_info(&timebaseInfo)
        return timebaseInfo
    }()

    // Use continuous system time so elapsed-time checks continue to advance while the device sleeps.
    var now: TimeInterval {
        let elapsedTicks = mach_continuous_time()
        let elapsedNanoseconds = Double(elapsedTicks) * Double(Self.timebaseInfo.numer) / Double(Self.timebaseInfo.denom)
        return elapsedNanoseconds / 1_000_000_000
    }
}
