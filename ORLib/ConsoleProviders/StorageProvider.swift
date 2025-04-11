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

import UIKit

public class StorageProvider: NSObject {

    let userdefaults = UserDefaults(suiteName: DefaultsKey.groupEntitlement)

    public func initialize() -> [String: Any] {
        return [
            DefaultsKey.actionKey: Actions.providerInit,
            DefaultsKey.providerKey: Providers.storage,
            DefaultsKey.versionKey: "1.0.0",
            DefaultsKey.requiresPermissionKey: false,
            DefaultsKey.hasPermissionKey: true,
            DefaultsKey.successKey: true,
            DefaultsKey.enabledKey: true
        ]
    }

    public func enable() -> [String: Any] {
        return [
            DefaultsKey.actionKey: Actions.providerEnable,
            DefaultsKey.providerKey: Providers.storage,
            DefaultsKey.hasPermissionKey: true,
            DefaultsKey.successKey: true,
        ]
    }

    public func store(key: String, data: String?) {
        if let dataToStore = data {
            userdefaults?.set(dataToStore, forKey: key)
        } else {
            userdefaults?.removeObject(forKey: key)
        }
        userdefaults?.synchronize()
    }

    public func retrieve(key: String) -> [String: Any?] {
        return [
            DefaultsKey.actionKey: Actions.retrieve,
            DefaultsKey.providerKey: Providers.storage,
            "key": key,
            "value": userdefaults?.string(forKey:key) ?? nil
        ]
    }

    public func disable()-> [String: Any] {
        return [
            DefaultsKey.actionKey: Actions.providerDisable,
            DefaultsKey.providerKey: Providers.storage
        ]
    }
}
