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
import OSLog
import UIKit
import WebKit

open class ORViewcontroller : UIViewController {
    private static let logger = Logger(
           subsystem: Bundle.main.bundleIdentifier!,
           category: String(describing: ORViewcontroller.self)
       )

    lazy var offlineViewController: UIViewController = {
        ViewControllerFactory.createOfflineViewController()
    }()
    var offlineVIewControllerPresented = false
    
    var data : Data?
    var myWebView : WKWebView?
    var webProgressBar: UIProgressView?
    var defaults : UserDefaults?
    var webCfg : WKWebViewConfiguration?
    var connectivityChecker: ConnectivityChecker?
    public var geofenceProvider: GeofenceProvider?
    public var pushProvider: PushNotificationProvider?
    public var storageProvider = StorageProvider()
    public var qrProvider: QrScannerProvider?
    public var bleProvider: BleProvider?

    // TODO: do I want to make this public ?
    var espProvisionProvider: ESPProvisionProvider?

    public var baseUrl: String?
    
    public var targetUrl: String?
    
    deinit {
        self.connectivityChecker?.stopMonitoring()
    }
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.white
        self.configureAccess()
        
        self.offlineViewController.modalPresentationStyle = .fullScreen
        self.connectivityChecker = ConnectivityChecker()
        self.connectivityChecker!.delegate = self
        self.connectivityChecker!.startMonitoring()
    }
    
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if let targetUrl = targetUrl {
            if let urlString = targetUrl.stringByURLEncoding() {
                if let url = URL(string: urlString) {
                    loadURL(url: url)
                }
            }
        }
        if (!self.connectivityChecker!.hasInternet()) {
            self.present(self.offlineViewController, animated: true)
            self.offlineVIewControllerPresented = true
        }
    }
    
    func sendData(data: [String: Any?]) {
        if let theJSONData = try? JSONSerialization.data(
            withJSONObject: data,
            options: []) {
            if let theJSONText = String(data: theJSONData,
                                        encoding: .utf8) {
                Self.logger.info("Sending to webapp \(theJSONText)")

                let returnMessage = "OpenRemoteConsole._handleProviderResponse('\(theJSONText)')"
                DispatchQueue.main.async {
                    self.myWebView?.evaluateJavaScript("\(returnMessage)", completionHandler: { (any, error) in
                        if let err = error {
                            print(err)
                        }
                    })
                }
            }
        }
    }
    
    func configureAccess() {
        if let currentWebView = myWebView {
            currentWebView.removeFromSuperview()
        }
        if let currentWebProgressBar = webProgressBar {
            currentWebProgressBar.removeFromSuperview()
        }
        
        let webCfg:WKWebViewConfiguration = WKWebViewConfiguration()
        let userController:WKUserContentController = WKUserContentController()
        
        userController.add(self, name: "int")
        
        let exec_template : String? = ""
        let userScript:WKUserScript = WKUserScript(source: exec_template!, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        userController.addUserScript(userScript)
        
        webCfg.userContentController = userController;
        let sbHeight: CGFloat

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            // Use the statusBarManager's frame if available
            sbHeight = windowScene.statusBarManager?.statusBarFrame.height ?? 0
        } else {
            // Fallback in case there's no window scene (this case is rare in iOS 13+ apps)
            sbHeight = 0
        }

        
        webCfg.allowsInlineMediaPlayback = true
        let webFrame = CGRect(x: 0, y: sbHeight, width: view.frame.size.width, height: view.frame.size.height - sbHeight)
        myWebView = WKWebView(frame: webFrame, configuration: webCfg)
        myWebView?.autoresizingMask = [.flexibleWidth, .flexibleHeight];
        myWebView?.navigationDelegate = self;
        //add observer to get estimated progress value
        myWebView?.addObserver(self, forKeyPath: "estimatedProgress", options: .new, context: nil);
        myWebView?.allowsBackForwardNavigationGestures = true
        myWebView?.scrollView.contentInsetAdjustmentBehavior = .never
        
        webProgressBar = UIProgressView(progressViewStyle: .bar)
        webProgressBar?.progressTintColor = UIColor(named: "or_green")
        
        if #available(macOS 13.3, iOS 16.4, tvOS 16.4, *) {
            myWebView?.isInspectable = true
        }
        
        view.addSubview(myWebView!)
        view.addSubview(webProgressBar!)
        view.bringSubviewToFront(webProgressBar!)
        
        webProgressBar?.translatesAutoresizingMaskIntoConstraints = false
        webProgressBar?.leadingAnchor.constraint(equalTo: myWebView!.leadingAnchor).isActive = true
        webProgressBar?.trailingAnchor.constraint(equalTo: myWebView!.trailingAnchor).isActive = true
        webProgressBar?.topAnchor.constraint(equalTo: myWebView!.topAnchor, constant: -2).isActive = true
        webProgressBar?.heightAnchor.constraint(equalToConstant: 2).isActive = true
    }
    
    func clearWebBackForwardList() {
        if let webView = myWebView {
            if webView.backForwardList.backList.count > 1 { //Check if there's more than one item before the current page in order to prevent an endless loop
                if let currentUrl = webView.url {
                    // the backForwardList of WKWebView is readonly, so need to create a new webview and set the currentUrl
                    configureAccess()
                    loadURL(url: currentUrl)
                }
            }
        }
    }
    
    public override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            if let webView = myWebView {
                webProgressBar?.progress = Float(webView.estimatedProgress);
            }
        }
    }
    
    func showProgressView() {
        if let progressBar = webProgressBar {
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
                progressBar.alpha = 1
            }, completion: nil)
        }
    }
    
    func hideProgressView() {
        if let progressBar = webProgressBar {
            UIView.animate(withDuration: 0.5, delay: 0, options: .curveEaseInOut, animations: {
                progressBar.alpha = 0
            }, completion: nil)
        }
    }
    
    public func loadURL(url : URL) {
        _ = self.myWebView?.load(URLRequest(url:url))
    }
    
    internal func handleError(errorCode: Int, description: String, failingUrl: String, isForMainFrame: Bool) {
        print("Error requesting '\(failingUrl)': \(errorCode) (\(description))")
        
        if !self.offlineVIewControllerPresented {
            let alertView = UIAlertController(title: "Error", message: "Error requesting '\(failingUrl)': \(errorCode) (\(description))", preferredStyle: .alert)
            
            if self.presentingViewController != nil {
                alertView.addAction(UIAlertAction(title: "OK", style: .default, handler: { _ in self.dismiss(animated: true)} ))
            } else {
                alertView.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            }
            self.present(alertView, animated: true, completion: nil)
        }
        
        /*
         if (false) {
         //TODO need to have case to return to home url of config or go back to wizard to setup project enviroment
         //            self.myWebView?.load(URLRequest(url: URL(string: url.stringByURLEncoding()!)!))
         } else {
         if self.presentingViewController != nil {
         self.dismiss(animated: true) {
         
         // TODO: this original code is causing error
         // self.presentingViewController!.present(alertView, animated: true, completion: nil)
         }
         } else {
         self.present(alertView, animated: true, completion: nil)
         }
         }
         */
    }
}

extension ORViewcontroller: WKScriptMessageHandler {
    public func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let jsonDictionnary = message.body as? [String : Any]
        Self.logger.info("Received from WebApp \(jsonDictionnary ?? [:])")
        if let type = jsonDictionnary?["type"] as? String {
            switch (type) {
            case "provider":
                if let postMessageDict = jsonDictionnary?[DefaultsKey.dataKey] as? [String: Any] {
                    if let action = postMessageDict[DefaultsKey.actionKey] as? String {
                        if let provider = postMessageDict[DefaultsKey.providerKey] as? String  {
                            switch (provider) {
                            case Providers.push:
                                switch(action) {
                                case Actions.providerInit:
                                    pushProvider = PushNotificationProvider()
                                    pushProvider!.initialize(callback: { initalizeData in
                                        self.sendData(data: initalizeData)
                                    })
                                case Actions.providerEnable:
                                    let consoleId = postMessageDict[GeofenceProvider.consoleIdKey] as? String
                                    pushProvider?.enable(consoleId: consoleId, callback: { enableData in
                                        self.sendData(data: enableData)
                                    })

                                case Actions.providerDisable:
                                    if let disableData = pushProvider?.disable() {
                                        sendData(data: disableData)
                                    }
                                default:
                                    print("Wrong action \(action) for \(provider)")
                                }
                            case Providers.geofence:
                                switch(action) {
                                case Actions.providerInit:
                                    geofenceProvider = GeofenceProvider()
                                    let initializeData = geofenceProvider!.initialize()
                                    sendData(data: initializeData)
                                case Actions.providerEnable:
                                    let consoleId = postMessageDict[GeofenceProvider.consoleIdKey] as? String
                                    if let userdefaults = UserDefaults(suiteName: DefaultsKey.groupEntitlement){
                                        let host = userdefaults.string(forKey: DefaultsKey.hostKey) ?? ""
                                        let realm = userdefaults.string(forKey: DefaultsKey.realmKey) ?? ""
                                        let baseUrl = host.isEmpty ? "" : host.appending("/api/\(realm)")
                                        geofenceProvider?.enable(baseUrl: baseUrl, consoleId: consoleId,  callback: { enableData in
                                            self.sendData(data: enableData)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(5)) {
                                                self.geofenceProvider?.fetchGeofences()
                                            }
                                        })
                                    }

                                case Actions.providerDisable:
                                    if let disableData = geofenceProvider?.disable() {
                                        sendData(data: disableData)
                                    }
                                case Actions.geofenceRefresh:
                                    geofenceProvider?.refreshGeofences()
                                default:
                                    print("Wrong action \(action) for \(provider)")
                                }
                            case Providers.storage:
                                switch(action) {
                                case Actions.providerInit:
                                    let initializeData = storageProvider.initialize()
                                    sendData(data: initializeData)
                                case Actions.providerEnable:
                                    let enableData = storageProvider.enable()
                                    sendData(data: enableData)

                                case Actions.providerDisable:
                                    let disableData = storageProvider.disable()
                                    sendData(data: disableData)
                                case Actions.store:
                                    if let key = postMessageDict["key"] as? String {
                                        storageProvider.store(key: key, data: postMessageDict["value"] as? String)
                                    }
                                case Actions.retrieve:
                                    if let key = postMessageDict["key"] as? String {
                                        let retrieveData = storageProvider.retrieve(key: key)
                                        sendData(data: retrieveData)
                                    }
                                default:
                                    print("Wrong action \(action) for \(provider)")
                                }
                            case Providers.qr:
                                switch (action) {
                                case Actions.providerInit:
                                    qrProvider = QrScannerProvider()
                                    qrProvider!.initialize(callback: { initializeData in
                                        self.sendData(data: initializeData)
                                    })
                                case Actions.providerEnable:
                                    qrProvider?.enable(callback: { enableData in
                                        self.sendData(data: enableData)
                                    })
                                case Actions.providerDisable:
                                    if let disableData = qrProvider?.disable() {
                                        sendData(data: disableData)
                                    }
                                case Actions.scanQr:
                                    qrProvider?.startScanner(currentViewController: self, startScanCallback: { startScanData in
                                        self.sendData(data: startScanData)
                                    }, scannedCallback:
                                                                { scannedData in
                                        self.sendData(data: scannedData)
                                    })
                                default:
                                    print("Wrong action \(action) for \(provider)")
                                }
                            case Providers.ble:
                                switch (action) {
                                case Actions.providerInit:
                                    bleProvider = BleProvider()
                                    bleProvider!.alertBluetoothCallback = {
                                        let alertController = UIAlertController(title: "Bluetooth disabled", message: "Please turn on bluetooth to scan for devices", preferredStyle: .alert)
                                        alertController.addAction(UIAlertAction(title: "OK", style: .default) { alertAction in
                                            let url = URL(string: UIApplication.openSettingsURLString)
                                            let app = UIApplication.shared
                                            app.open(url!, options: [:])
                                        })
                                        alertController.addAction(UIAlertAction(title: "Not now", style: .cancel))
                                        self.present(alertController, animated: true)
                                    }
                                    self.sendData(data: bleProvider!.initialize())
                                case Actions.providerEnable:
                                    bleProvider?.enable(callback: { enableData in
                                        self.sendData(data: enableData)
                                    })
                                case Actions.providerDisable:
                                    if let disableData = bleProvider?.disable() {
                                        sendData(data: disableData)
                                    }
                                case Actions.scanBleDevices:
                                    bleProvider?.scanForDevices { scanData in
                                        self.sendData(data: scanData)
                                    }
                                case Actions.connectToBleDevice:
                                    if let deviceId = postMessageDict["address"] as? String {
                                        bleProvider?.connectoToDevice(deviceId: deviceId) { connectData in
                                            self.sendData(data: connectData)
                                        }
                                    }
                                case Actions.disconnectFromBleDevice:
                                    bleProvider?.disconnectFromDevice() {disconnectData in
                                        self.sendData(data: disconnectData)
                                    }
                                case Actions.sendToBleDevice:
                                    if let attributeId = postMessageDict["attributeId"] as? String, let value = postMessageDict["value"] {
                                        if let data = try? JSONSerialization.data(
                                            withJSONObject: value,
                                            options: []) {
                                            bleProvider?.sendToDevice(attributeId: attributeId, value: data) { sendData in
                                                self.sendData(data: sendData)
                                            }
                                        }
                                    }
                                default:
                                    print("Wrong action \(action) for \(provider)")
                                }
                            case Providers.espprovision:
                                switch(action) {
                                case Actions.providerInit:
                                    if let baseUrl, let appUrl = URL(string: baseUrl),

                                        // TODO: should use realm, not always master
                                       let apiUrl = URL(string: "\(appUrl.scheme ?? "https")://\(appUrl.host ?? "localhost")\(appUrl.port != nil ? ":\(appUrl.port!)" : "")/api/master") {
                                        espProvisionProvider = ESPProvisionProvider(apiURL: apiUrl)
                                    } else {
                                        espProvisionProvider = ESPProvisionProvider()
                                    }
                                    espProvisionProvider?.sendDataCallback = { [weak self] data in
                                        self?.sendData(data: data)
                                    }
                                    self.sendData(data: espProvisionProvider!.initialize())
                                case Actions.providerEnable:
                                    espProvisionProvider?.enable()
                                case Actions.providerDisable:
                                    if let disableData = espProvisionProvider?.disable() {
                                        sendData(data: disableData)
                                    }
                                case Actions.startBleScan:
                                    espProvisionProvider?.startDevicesScan(prefix: postMessageDict["prefix"] as? String)
                                case Actions.stopBleScan:
                                    espProvisionProvider?.stopDevicesScan()
                                case Actions.connectToBleDevice:
                                    if let deviceId = postMessageDict["id"] as? String {
                                        espProvisionProvider?.connectTo(deviceId: deviceId, pop: postMessageDict["pop"] as? String)
                                    } else {
                                        let payload: [String: Any] = [
                                            DefaultsKey.providerKey: provider,
                                            DefaultsKey.actionKey: action,
                                            "errorCode": ESPProviderErrorCode.unknownDevice.rawValue,
                                            "errorMessage": "Missing id parameter"
                                        ]
                                        self.sendData(data: payload)
                                    }
                                case Actions.disconnectFromBleDevice:
                                    espProvisionProvider?.disconnectFromDevice()
                                case Actions.startWifiScan:
                                    espProvisionProvider?.startWifiScan()
                                case Actions.stopWifiScan:
                                    espProvisionProvider?.stopWifiScan()
                                case Actions.sendWifiConfiguration:
                                    if let ssid = postMessageDict["ssid"] as? String,
                                       let password = postMessageDict["password"] as? String {
                                        espProvisionProvider?.sendWifiConfiguration(ssid: ssid, password: password)
                                    } else {
                                        let payload: [String: Any] = [
                                            DefaultsKey.providerKey: provider,
                                            DefaultsKey.actionKey: action,
                                            "errorCode": ESPProviderErrorCode.wifiAuthenticationError.rawValue,
                                            "errorMessage": "Missing ssid or password parameter"
                                        ]
                                        self.sendData(data: payload)
                                    }
                                case Actions.exitProvisioning:
                                    espProvisionProvider?.exitProvisioning()
                                case Actions.provisionDevice:
                                    if let userToken = postMessageDict["userToken"] as? String {
                                        espProvisionProvider?.provisionDevice(userToken: userToken)
                                    } else {
                                        let payload: [String: Any] = [
                                            DefaultsKey.providerKey: provider,
                                            DefaultsKey.actionKey: action,
                                            "errorCode": ESPProviderErrorCode.securityError.rawValue,
                                            "errorMessage": "Missing userToken parameter"
                                        ]
                                        self.sendData(data: payload)
                                    }
                                default:
                                    print("Wrong action \(action) for \(provider)")
                                }
                            default:
                                print("Unknown provider type: \(provider )")
                            }
                        }
                    }
                }
            case "CLEAR_WEB_HISTORY":
                clearWebBackForwardList()
                break
            default:
                print("Unknown message type: \(type )")
            }
        }
    }
}

extension ORViewcontroller: WKNavigationDelegate {
    
    public func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        showProgressView()
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if (navigationAction.request.url?.absoluteString.starts(with: "webbrowser"))! {
            if let url = navigationAction.request.url, var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                components.scheme = "https"
                if let newUrl = components.url {
                    UIApplication.shared.open(newUrl)
                }
            }
            decisionHandler(.cancel)
        }  else {
            let app = UIApplication.shared
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url{
                if app.canOpenURL(url) {
                    app.open(url)
                    decisionHandler(.cancel)
                }
            } else {
                if let baseUrl = self.baseUrl {
                    webView.loadCookiesFromStorage(for: baseUrl) {
                        decisionHandler(.allow)
                    }
                } else {
                    decisionHandler(.allow)
                }
            }
        }
    }
    
    public func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if let response = navigationResponse.response as? HTTPURLResponse {
            if response.statusCode != 200 && response.statusCode != 204 {
                decisionHandler(.cancel)
                
                if 400...499 ~= response.statusCode {
                    if let baseUrl = self.baseUrl {
                        webView.clearCookies(for: baseUrl, completion: nil)
                    }
                }
                
                handleError(errorCode: response.statusCode, description: "Error in request", failingUrl: response.url?.absoluteString ?? "", isForMainFrame: true)
                return
            }
        }
        if let baseUrl = self.baseUrl {
            webView.writeCookiesToStorage(for: baseUrl) {
                decisionHandler(.allow)
            }
        } else {
            decisionHandler(.allow)
        }
    }
    
    public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        NSLog("error %@", error.localizedDescription)
        if let err = error as? URLError {
            
            let httpCode: Int
            switch(err.code) {
            case .cannotFindHost:
                httpCode = 404
            default:
                httpCode = 500
            }
            
            handleError(errorCode: httpCode, description: err.localizedDescription, failingUrl: err.failureURLString ?? "", isForMainFrame: true)
        } else {
            handleError(errorCode: 0, description: error.localizedDescription, failingUrl: webView.url?.absoluteString ?? "", isForMainFrame: true)
        }
    }
    
    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        hideProgressView()
    }
    
    public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        NSLog("error %@", error.localizedDescription)
        if let err = error as? URLError {
            
            let httpCode: Int
            switch(err.code) {
            case .cannotFindHost:
                httpCode = 404
            default:
                httpCode = 500
            }
            
            handleError(errorCode: httpCode, description: err.localizedDescription, failingUrl: err.failureURLString ?? "", isForMainFrame: true)
        } else {
            handleError(errorCode: 0, description: error.localizedDescription, failingUrl: webView.url?.absoluteString ?? "", isForMainFrame: true)
        }
        hideProgressView()
    }
    
    func reloadWebView() {
        var url = self.myWebView?.url
            
        if url?.absoluteString == "about:blank" || url == nil {
            url = URL(string: baseUrl!)
        }
        self.loadURL(url: url!)
    }
}

extension ORViewcontroller: ConnectivityDelegate {
    func connectivityStatusDidChange(isConnected: Bool) {
        DispatchQueue.main.async {
            print("connection changed \(isConnected)")
            if isConnected {
                if (self.offlineVIewControllerPresented) {
                    self.reloadWebView()
                    self.offlineViewController.dismiss(animated: true)
                }
            } else {
                if (!self.offlineVIewControllerPresented) {
                    self.showToast(message: "Check your internet connection")
                }
            }
        }
    }
}
