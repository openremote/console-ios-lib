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
import UserNotifications

public class PushNotificationProvider: NSObject {

    typealias AuthorizationStatus = (@escaping (UNAuthorizationStatus) -> Void) -> Void
    typealias RequestAuthorization = (@escaping (Bool) -> Void) -> Void
    typealias Register = () -> Void

    let userdefaults: UserDefaults?
    let center: NotificationCenter
    private let authorizationStatus: AuthorizationStatus
    private let requestAuthorization: RequestAuthorization
    private let register: Register
    let version = "fcm"
    public var consoleId: String?
    public static let pushDisabledKey = "pushDisabled"
    public static let tokenKey = "token"

    /// How long to wait for the FCM token before replying to an enable request,
    /// the web console stops waiting for a provider reply after 5 seconds (`sendProviderMessage` in openremote `console.ts`)
    static let tokenWaitTimeout: TimeInterval = 4.5

    public override convenience init() {
        self.init(center: .default, userdefaults: UserDefaults(suiteName: DefaultsKey.groupEntitlement))
    }

    init(center: NotificationCenter,
         userdefaults: UserDefaults?,
         authorizationStatus: @escaping AuthorizationStatus = PushNotificationProvider.currentAuthorizationStatus,
         requestAuthorization: @escaping RequestAuthorization = PushNotificationProvider.requestUserAuthorization,
         register: @escaping Register = PushNotificationProvider.registerForRemoteNotifications) {
        self.center = center
        self.userdefaults = userdefaults
        self.authorizationStatus = authorizationStatus
        self.requestAuthorization = requestAuthorization
        self.register = register
        super.init()
    }

    public func initialize(callback: @escaping ([String: Any?]) -> Void) {
        authorizationStatus { status in
            switch status {

            case .authorized, .provisional:
                callback( [
                    DefaultsKey.actionKey: Actions.providerInit,
                    DefaultsKey.providerKey: Providers.push,
                    DefaultsKey.versionKey: self.version,
                    DefaultsKey.hasPermissionKey: true,
                    DefaultsKey.requiresPermissionKey: true,
                    DefaultsKey.successKey: true,
                    DefaultsKey.enabledKey: false,
                    DefaultsKey.disabledKey: self.userdefaults?.bool(forKey: PushNotificationProvider.pushDisabledKey) ?? false
                    ])

            case .denied:
                callback( [
                    DefaultsKey.actionKey: Actions.providerInit,
                    DefaultsKey.providerKey: Providers.push,
                    DefaultsKey.versionKey: self.version,
                    DefaultsKey.hasPermissionKey: false,
                    DefaultsKey.requiresPermissionKey: true,
                    DefaultsKey.successKey: true,
                    DefaultsKey.enabledKey: false,
                    DefaultsKey.disabledKey: self.userdefaults?.bool(forKey: PushNotificationProvider.pushDisabledKey) ?? false
                    ])

            default:
                callback( [
                    DefaultsKey.actionKey: Actions.providerInit,
                    DefaultsKey.providerKey: Providers.push,
                    DefaultsKey.versionKey: self.version,
                    DefaultsKey.hasPermissionKey: nil,
                    DefaultsKey.requiresPermissionKey: true,
                    DefaultsKey.successKey: true,
                    DefaultsKey.enabledKey: false,
                    DefaultsKey.disabledKey: self.userdefaults?.bool(forKey: PushNotificationProvider.pushDisabledKey) ?? false
                    ])
            }
        }
    }

    /// Replies once the FCM token is available (or the wait times out), so the console registration includes it.
    /// On first launch the token is only delivered by Firebase after registering for remote notifications.
    public func enable(consoleId: String?, callback: @escaping ([String: Any]) -> Void) {
        self.consoleId = consoleId
        if self.consoleId != nil {
            userdefaults?.set(self.consoleId!, forKey: GeofenceProvider.consoleIdKey)
            userdefaults?.removeObject(forKey: PushNotificationProvider.pushDisabledKey)
            userdefaults?.synchronize()
        }
        let deadline = Date().addingTimeInterval(PushNotificationProvider.tokenWaitTimeout)
        authorizationStatus { status in

            switch status {
            case .authorized, .provisional:
                self.register()
                self.waitForToken(until: deadline) { token in
                    callback(self.enableResponse(hasPermission: true, token: token))
                }

            case .denied:
                callback(self.enableResponse(hasPermission: false, token: self.cachedToken))

            default:
                // The token does not depend on the user's answer, so don't make the reply wait for the prompt
                // (which could exceed the web console timeout). Same as the Android console.
                var granted: Bool?
                self.register()
                self.requestAuthorization { isGranted in
                    DispatchQueue.main.async { granted = isGranted }
                }
                self.waitForToken(until: deadline) { token in
                    callback(self.enableResponse(hasPermission: granted ?? true, token: token))
                }
            }
        }
    }

    public func disable() -> [String: Any] {
        userdefaults?.set(true, forKey: PushNotificationProvider.pushDisabledKey)
        userdefaults?.synchronize()
        return [
            DefaultsKey.actionKey: Actions.providerDisable,
            DefaultsKey.providerKey: Providers.push
        ]
    }

    /// Completes on the main thread with the cached token, or the token posted through `Notifications.pushTokenUpdated`,
    /// or whatever is cached once the deadline is reached
    func waitForToken(until deadline: Date, completion: @escaping (String?) -> Void) {
        DispatchQueue.main.async {
            if let token = self.cachedToken {
                completion(token)
                return
            }

            var observer: NSObjectProtocol?
            var finished = false
            let finish: (String?) -> Void = { token in
                guard !finished else { return }
                finished = true
                if let observer = observer {
                    self.center.removeObserver(observer)
                }
                completion(token)
            }

            observer = self.center.addObserver(forName: Notifications.pushTokenUpdated, object: nil, queue: .main) { notification in
                finish(notification.userInfo?[PushNotificationProvider.tokenKey] as? String ?? self.cachedToken)
            }
            // The token might have been stored between the first check and adding the observer
            if let token = self.cachedToken {
                finish(token)
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow)) {
                finish(self.cachedToken)
            }
        }
    }

    private var cachedToken: String? {
        userdefaults?.string(forKey: DefaultsKey.fcmTokenKey)
    }

    static func currentAuthorizationStatus(_ completion: @escaping (UNAuthorizationStatus) -> Void) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            completion(settings.authorizationStatus)
        }
    }

    static func requestUserAuthorization(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            completion(granted)
        }
    }

    static func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    private func enableResponse(hasPermission: Bool, token: String?) -> [String: Any] {
        return [
            DefaultsKey.actionKey: Actions.providerEnable,
            DefaultsKey.providerKey: Providers.push,
            DefaultsKey.hasPermissionKey: hasPermission,
            DefaultsKey.successKey: true,
            DefaultsKey.dataKey: [PushNotificationProvider.tokenKey: token]
        ]
    }
}
