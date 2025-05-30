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

/// A communication channel back to the web app
struct CallbackChannel {

    private var sendDataCallback: SendDataCallback

    private var provider: String

    init(sendDataCallback: @escaping SendDataCallback, provider: String) {
        self.sendDataCallback = sendDataCallback
        self.provider = provider
    }

    func sendMessage(action: String, data: [String: Any]?) {
        var payload: [String: Any] = [
            DefaultsKey.providerKey: provider,
            DefaultsKey.actionKey: action]
        if let data {
            payload.merge(data) { current, _ in
                current
            }
        }
        self.sendDataCallback(payload)
    }

}
