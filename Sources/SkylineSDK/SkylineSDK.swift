import Foundation
import UIKit
import AppsFlyerLib
import Alamofire
import SwiftUI
import FBSDKCoreKit
import FBAEMKit
import AppTrackingTransparency
import AdSupport
import SdkPushExpress
import Combine


public class SkylineSDK: NSObject , AppsFlyerLibDelegate {
    
    @AppStorage("savedData") var savedData: String?
    @AppStorage("initialURL") var initialURL: String?
    @AppStorage("statusFlag") var statusFlag: Bool = false
    
    public func onConversionDataSuccess(_ conversionInfo: [AnyHashable : Any]) {
        var conversionData = [String: Any]()

        conversionData[appsIDString] = AppsFlyerLib.shared().getAppsFlyerUID()
        conversionData[appsDataString] = conversionInfo
        conversionData[tokenString] = deviceToken
        conversionData[langString] = Locale.current.languageCode

        let jsonData = try! JSONSerialization.data(withJSONObject: conversionData, options: .fragmentsAllowed)
        let jsonString = String(data: jsonData, encoding: .utf8) ?? ""

        sendDataToServer(code: jsonString) { result in
            switch result {
            case .success(let message):
                self.sendNotification(name: "SkylineSDKNotification", message: message)
            case .failure:
                self.sendNotificationError(name: "SkylineSDKNotification")
            }
        }
    }
    
    public func onConversionDataFail(_ error: any Error) {
        self.sendNotificationError(name: "SkylineSDKNotification")
    }
    
    private func sendNotification(name: String, message: String) {
        DispatchQueue.main.async {
            self.showWeb(with: message)
        }
    }
    
    
    private func sendNotificationError(name: String) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(name),
                object: nil,
                userInfo: ["notificationMessage": "Error occurred"]
            )
        }
    }
    
    public static let shared = SkylineSDK()
    private var hasSessionStarted = false
    private var deviceToken: String = ""
    private var session: Session
    private var cancellables = Set<AnyCancellable>()

    
    private var appsDataString: String = ""
    private var appsIDString: String = ""
    private var langString: String = ""
    private var tokenString: String = ""
    
    private var domen: String = ""
    private var paramName: String = ""
    private var mainWindow: UIWindow?
    
    private override init() {
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = 20
        sessionConfig.timeoutIntervalForResource = 20
        self.session = Alamofire.Session(configuration: sessionConfig)
    }

    public func initialize(
        appsFlyerKey: String,
        appID: String,
        pushExpressKey: String,
        appsDataString: String,
        appsIDString: String,
        langString: String,
        tokenString: String,
        domen: String,
        paramName: String,
        application: UIApplication,
        window: UIWindow,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        
        self.appsDataString = appsDataString
        self.appsIDString = appsIDString
        self.langString = langString
        self.tokenString = tokenString
        self.domen = domen
        self.paramName = paramName
        self.mainWindow = window

        ApplicationDelegate.shared.application(application, didFinishLaunchingWithOptions: nil)
        Settings.shared.isAdvertiserIDCollectionEnabled = true
        Settings.shared.isAutoLogAppEventsEnabled = true

        // Инициализация PushExpress
        try? PushExpressManager.shared.initialize(appId: pushExpressKey)

        // Инициализация AppsFlyer
        AppsFlyerLib.shared().appsFlyerDevKey = appsFlyerKey
        AppsFlyerLib.shared().appleAppID = appID
        AppsFlyerLib.shared().delegate = self
        AppsFlyerLib.shared().waitForATTUserAuthorization(timeoutInterval: 15)
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleSessionDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        
        completion(.success("Initialization completed successfully"))
    }

    public func registerForRemoteNotifications(deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        PushExpressManager.shared.transportToken = tokenString
        self.deviceToken = tokenString
    }

    @objc private func handleSessionDidBecomeActive() {
        if !self.hasSessionStarted {
            AppsFlyerLib.shared().start()
            self.hasSessionStarted = true

            ATTrackingManager.requestTrackingAuthorization { _ in }
        }
    }

    public func sendDataToServer(code: String, completion: @escaping (Result<String, Error>) -> Void) {
        let parameters = [paramName: code]

        session.request(domen, method: .get, parameters: parameters)
            .validate()
            .responseDecodable(of: ResponseData.self) { response in
                switch response.result {
                case .success(let decodedData):
                    PushExpressManager.shared.tags["webmaster"] = decodedData.naming
                    self.statusFlag = decodedData.first_link
                    try? PushExpressManager.shared.activate()
                    
                    if self.initialURL == nil {
                        self.initialURL = decodedData.naming
                        if self.statusFlag {
                            self.savedData = decodedData.naming
                        }
                        completion(.success(decodedData.link))
                    } else if decodedData.link == self.initialURL {
                        if self.savedData == nil {
                            if self.statusFlag {
                                self.savedData = decodedData.link
                            }
                            completion(.success(decodedData.link))
                        } else {
                            completion(.success(self.savedData!))
                        }
                    } else {
                        self.savedData = nil
                        self.initialURL = decodedData.link
                        if self.statusFlag {
                            self.savedData = decodedData.link
                        }
                        completion(.success(decodedData.link))
                    }
                    
                   
                case .failure:
                    try? PushExpressManager.shared.activate()
                    completion(.failure(NSError(domain: "SkylineSDK", code: -1, userInfo: [NSLocalizedDescriptionKey: "Error occurred"])))
                }
            }
    }
    
    struct ResponseData: Codable {
        var link: String
        var naming: String
        var first_link: Bool
    }

    
    func showWeb(with: String){
        self.mainWindow = UIWindow(frame: UIScreen.main.bounds)
        let webController = WebController()
        webController.errorURL = with
        let navController = UINavigationController(rootViewController: webController)
        self.mainWindow?.rootViewController = navController
        self.mainWindow?.makeKeyAndVisible()
    }
//    private var statusFlag: Bool = false


}
