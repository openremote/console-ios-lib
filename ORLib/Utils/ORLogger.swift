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
import os

public struct ORLogger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "io.openremote.orlib"

    public static let network = Logger(subsystem: subsystem, category: "Network")
    public static let bluetooth = Logger(subsystem: subsystem, category: "Bluetooth")
    public static let providers = Logger(subsystem: subsystem, category: "Providers")
    public static let espprovisioning = Logger(subsystem: subsystem, category: "ESPProvisioning")
    public static let webview = Logger(subsystem: subsystem, category: "WebView")
    public static let config = Logger(subsystem: subsystem, category: "Configuration")
    public static let geofence = Logger(subsystem: subsystem, category: "Geofence")
    public static let utils = Logger(subsystem: subsystem, category: "Utils")
    public static let test = Logger(subsystem: subsystem, category: "Test")
}
