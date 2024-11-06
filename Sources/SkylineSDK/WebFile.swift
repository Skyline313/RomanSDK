//
//  File.swift
//  
//
//  Created by Roman iMac on 06.11.2024.
//

import Foundation
import SwiftUI
import WebKit

class WebController: UIViewController {

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
    override func viewDidLoad() {
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

    override func viewWillAppear(_ animated: Bool) {
        navigationItem.largeTitleDisplayMode = .never
        navigationController?.isNavigationBarHidden = true
    }

    override func viewDidDisappear(_ animated: Bool) {
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

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url, UIApplication.shared.canOpenURL(url) {
            var urlRequest = URLRequest(url: url)
            urlRequest.cachePolicy = .returnCacheDataElseLoad
            webView.load(urlRequest)
        }
        decisionHandler(.allow)
    }
}

extension WebController: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
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

struct WebControllerSwiftUI: UIViewControllerRepresentable {
    var errorDetail: String

    func makeUIViewController(context: Context) -> WebController {
        let viewController = WebController()
        viewController.errorURL = errorDetail
        return viewController
    }

    func updateUIViewController(_ uiViewController: WebController, context: Context) {}
}
