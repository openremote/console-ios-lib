/*
 * Copyright 2026, OpenRemote Inc.
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

/// A UserDefaults suite private to one test, removed from disk once nothing references it anymore
final class TemporaryUserDefaults: UserDefaults {
    private let suiteName: String

    // Labelled because a failable init() can't override UserDefaults.init()
    init?(uniqueId: String = UUID().uuidString) {
        let suiteName = "ORLibTests.\(uniqueId)"
        self.suiteName = suiteName
        super.init(suiteName: suiteName)
    }

    deinit {
        removePersistentDomain(forName: suiteName)
    }
}
