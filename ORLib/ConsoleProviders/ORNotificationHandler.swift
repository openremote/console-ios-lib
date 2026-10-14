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

import UIKit
import UserNotifications

/// Handles push notification related callbacks on behalf of console apps.
///
/// The app owns the Firebase setup: call `FirebaseApp.configure()` and set `Messaging.messaging().delegate` on every
/// launch path, and set `Messaging.messaging().apnsToken` in `didRegisterForRemoteNotificationsWithDeviceToken`
/// when Firebase method swizzling is disabled. Without an APNs token Firebase never delivers an FCM token.
///
/// Apps forward their `UNUserNotificationCenterDelegate` and Firebase `MessagingDelegate` callbacks to the shared instance:
/// ```swift
/// func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
///                             withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
///     completionHandler(ORNotificationHandler.shared.willPresent(notification))
/// }
///
/// func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
///                             withCompletionHandler completionHandler: @escaping () -> Void) {
///     ORNotificationHandler.shared.didReceive(response)
///     completionHandler()
/// }
///
/// func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
///     ORNotificationHandler.shared.didReceiveRegistrationToken(fcmToken)
/// }
/// ```
public final class ORNotificationHandler {

    public static let shared = ORNotificationHandler()

    typealias Delivered = (_ notificationId: Int64, _ consoleId: String) -> Void
    typealias Acknowledge = (_ notificationId: Int64, _ consoleId: String, _ acknowledgement: String) -> Void
    typealias Open = (_ url: URL, _ inBrowser: Bool) -> Void
    typealias Send = (_ request: URLRequest) -> Void

    static let declineActionIdentifier = "declineAction"

    // Resolved on each use as apps can change DefaultsKey.groupEntitlement at launch
    private let defaults: () -> UserDefaults?
    private let center: NotificationCenter
    private let delivered: Delivered
    private let acknowledge: Acknowledge
    private let open: Open
    private let send: Send

    init(defaults: @escaping () -> UserDefaults? = { UserDefaults(suiteName: DefaultsKey.groupEntitlement) },
         center: NotificationCenter = .default,
         delivered: @escaping Delivered = { ORNotificationResource.sharedInstance.notificationDelivered(notificationId: $0, targetId: $1) },
         acknowledge: @escaping Acknowledge = {
            ORNotificationResource.sharedInstance.notificationAcknowledged(notificationId: $0, targetId: $1, acknowledgement: $2)
         },
         open: @escaping Open = ORNotificationHandler.openURL,
         send: @escaping Send = ORNotificationHandler.sendRequest) {
        self.defaults = defaults
        self.center = center
        self.delivered = delivered
        self.acknowledge = acknowledge
        self.open = open
        self.send = send
    }

    // MARK: - MessagingDelegate

    /// Stores the FCM token and notifies a push provider waiting for it.
    /// A rotated token reaches the backend the next time the console enables push (on every page load).
    public func didReceiveRegistrationToken(_ token: String?) {
        guard let token = token else {
            ORLogger.providers.info("No FCM token")
            return
        }
        ORLogger.providers.info("FCM registration token: \(token)")
        if let defaults = defaults() {
            defaults.set(token, forKey: DefaultsKey.fcmTokenKey)
            defaults.synchronize()
        }
        center.post(name: Notifications.pushTokenUpdated, object: nil, userInfo: [PushNotificationProvider.tokenKey: token])
    }

    // MARK: - UNUserNotificationCenterDelegate

    public func willPresent(_ notification: UNNotification) -> UNNotificationPresentationOptions {
        handleWillPresent(userInfo: notification.request.content.userInfo)
        return [.banner, .sound]
    }

    public func didReceive(_ response: UNNotificationResponse) {
        handleResponse(userInfo: response.notification.request.content.userInfo, actionIdentifier: response.actionIdentifier)
    }

    func handleWillPresent(userInfo: [AnyHashable: Any]) {
        if let notificationId = notificationId(in: userInfo), let consoleId = consoleId() {
            delivered(notificationId, consoleId)
        }
    }

    func handleResponse(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        ORLogger.providers.info("Notification action chosen: \(actionIdentifier)")

        switch actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            handleDefault(userInfo: userInfo)
        case UNNotificationDismissActionIdentifier, ORNotificationHandler.declineActionIdentifier:
            acknowledgeIfPossible(userInfo: userInfo, actionIdentifier: actionIdentifier)
        default:
            acknowledgeIfPossible(userInfo: userInfo, actionIdentifier: actionIdentifier)
            handleButton(userInfo: userInfo, actionIdentifier: actionIdentifier)
        }
    }

    // MARK: - Actions

    private func handleDefault(userInfo: [AnyHashable: Any]) {
        guard let path = userInfo[ActionType.appUrl] as? String, !path.isEmpty,
              let url = resolveURL(path, project: selectedProject()) else {
            return
        }
        open(url, userInfo[ActionType.openInBrowser] as? Bool ?? false)
    }

    private func handleButton(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        guard let buttonsData = (userInfo[DefaultsKey.buttonsKey] as? String)?.data(using: .utf8),
              let buttons = try? JSONDecoder().decode([ORPushNotificationButton].self, from: buttonsData),
              let action = buttons.first(where: { $0.title == actionIdentifier })?.action,
              let url = resolveURL(action.url, project: selectedProject()) else {
            return
        }
        perform(action, url: url)
    }

    private func perform(_ action: ORPushNotificationAction, url: URL) {
        if action.silent {
            var request = URLRequest(url: url)
            request.httpMethod = action.httpMethod ?? "GET"
            if let body = action.data {
                request.httpBody = body.data(using: .utf8)
                request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            }
            send(request)
        } else {
            open(url, action.openInBrowser)
        }
    }

    private func acknowledgeIfPossible(userInfo: [AnyHashable: Any], actionIdentifier: String) {
        if let notificationId = notificationId(in: userInfo), let consoleId = consoleId() {
            acknowledge(notificationId, consoleId, actionIdentifier)
        }
    }

    // MARK: - Helpers

    private func resolveURL(_ path: String, project: ProjectConfig?) -> URL? {
        if path.hasPrefix("http") {
            return URL(string: path)
        }
        guard let baseURL = project?.baseURL else { return nil }
        return URL(string: "\(baseURL)/console/\(path)")
    }

    private func selectedProject() -> ProjectConfig? {
        guard let defaults = defaults(),
              let projectsData = defaults.data(forKey: DefaultsKey.projectsConfigurationKey),
              let projects = try? JSONDecoder().decode([ProjectConfig].self, from: projectsData) else {
            return nil
        }
        let selectedProjectId = defaults.string(forKey: DefaultsKey.projectKey)
        return projects.first(where: { $0.id == selectedProjectId })
    }

    private func notificationId(in userInfo: [AnyHashable: Any]) -> Int64? {
        guard let notificationIdString = userInfo[ActionType.notificationId] as? String else { return nil }
        return Int64(notificationIdString)
    }

    // TODO: geofence provider should also be adapted to store "per project"
    private func consoleId() -> String? {
        defaults()?.string(forKey: GeofenceProvider.consoleIdKey)
    }

    static func openURL(_ url: URL, inBrowser: Bool) {
        DispatchQueue.main.async {
            if inBrowser {
                UIApplication.shared.open(url)
            } else {
                activeORViewController()?.loadURL(url: url)
            }
        }
    }

    static func sendRequest(_ request: URLRequest) {
        URLSession.shared.dataTask(with: request) { _, _, error in
            if let error = error {
                ORLogger.network.error("Notification action request failed: \(error.localizedDescription)")
            }
        }.resume()
    }

    /// Finds the console view controller across all scenes, works for both scene based and window based apps
    static func activeORViewController() -> ORViewcontroller? {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        let keyWindowsFirst = windows.filter { $0.isKeyWindow } + windows.filter { !$0.isKeyWindow }
        return topORViewController(in: keyWindowsFirst.compactMap { $0.rootViewController })
    }

    /// Returns the top-most console view controller presented from the first root that has one,
    /// non-console screens (offline, QR scanner) can be presented on top of it
    static func topORViewController(in roots: [UIViewController]) -> ORViewcontroller? {
        for root in roots {
            let presented = sequence(first: root) { $0.presentedViewController }
            if let found = presented.compactMap({ $0 as? ORViewcontroller }).last {
                return found
            }
        }
        return nil
    }
}
