//
//  BLEPermissionsChecker.swift
//  ORLib
//
//  Created by Eric Bariaux on 28/05/2025.
//

import Foundation
import CoreBluetooth

class BLEPermissionsChecker: NSObject {
    private var callbackChannel: CallbackChannel?

    private var manager: CBCentralManager?
    private var continuation: CheckedContinuation<Bool, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(callbackChannel: CallbackChannel?) {
        self.callbackChannel = callbackChannel
    }

    func checkPermissions() async -> Bool {
        if CBCentralManager.authorization == .allowedAlways {
            return true
        }

        let timeout = 60.0 // seconds

        return await withCheckedContinuation { continuation in
            self.continuation = continuation

            // This will trigger the iOS pop-up to provide authorization to use BLE
            // This is required otherwise permissionKey returned to the web app is always false
            let manager = CBCentralManager(delegate: self, queue: nil)

            // Keep a reference to manager or it does not request permissions
            self.manager = manager

            self.timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                if let continuation = self.continuation {
                    continuation.resume(returning: false)
                    self.continuation = nil
                }
            }
        }
    }

    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async -> T) async -> T? {
        await withTaskGroup(of: T?.self) { group in
            group.addTask { await operation() }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                return nil
            }

            return await group.next()!
        }
    }
}

extension BLEPermissionsChecker: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        timeoutTask?.cancel()
        timeoutTask = nil

        continuation?.resume(returning: CBCentralManager.authorization == .allowedAlways)
        continuation = nil
    }
}


