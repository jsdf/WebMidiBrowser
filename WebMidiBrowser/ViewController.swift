//
//  ViewController.swift
//  WebMidiBrowser
//
//  Created by James Friend on 3/23/21.
//  Copyright © 2021 jsdf. All rights reserved.
//

import UIKit
import WebKit
import Gong
import CoreMIDI

extension NSRegularExpression {
    convenience init(_ pattern: String) {
        do {
            try self.init(pattern: pattern)
        } catch {
            preconditionFailure("Illegal regular expression: \(pattern).")
        }
    }
}

extension NSRegularExpression {
    func matches(_ string: String) -> Bool {
        let range = NSRange(location: 0, length: string.utf16.count)
        return firstMatch(in: string, options: [], range: range) != nil
    }
}

class ViewController: UIViewController, WKNavigationDelegate {
    var webView: WKWebView!
    var progressView: UIProgressView!


    override func loadView() {
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: .zero, configuration: config)
        print("num sources", MIDIGetNumberOfSources())
        print("num devices", MIDIGetNumberOfDevices())
        MIDI.connect();
        print("midi.connect")
        for device in MIDIDevice.all {
            print(device.name)
        }
        webView.navigationDelegate = self
        view = webView
        let contentController = self.webView.configuration.userContentController
        contentController.add(self, name: "webMidiBrowser")
        let filepath = Bundle.main.path(forResource: "shim", ofType: "js")
        let js = try! String(contentsOfFile: filepath!)
        
        print("using js", js)
 

        let script = WKUserScript(source: js, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        contentController.addUserScript(script)

    }
    override func viewDidLoad() {
        super.viewDidLoad()
        let spacer = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        progressView = UIProgressView(progressViewStyle: .default)
        progressView.sizeToFit()
        let progressButton = UIBarButtonItem(customView: progressView)
        let refresh = UIBarButtonItem(barButtonSystemItem: .refresh, target: webView, action: #selector(webView.reload))
        let back = UIBarButtonItem(barButtonSystemItem: .rewind, target: webView, action: #selector(webView.goBack))
//        toolbarItems = [progressButton, spacer, refresh]
        
//        navigationController?.isToolbarHidden = false
        
        navigationItem.rightBarButtonItems = [refresh, back]
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Open", style: .plain, target: self, action: #selector(openTapped))

        if (true) {
            let url = URL(string: "https://jsdf.github.io/scaletoy/")!
            webView.load(URLRequest(url: url))
        } else {
            let url = Bundle.main.url(forResource: "index", withExtension: "html")!
            webView.loadFileURL(url, allowingReadAccessTo: url)
            webView.load(URLRequest(url: url))
        }
        webView.allowsBackForwardNavigationGestures = true
        webView.addObserver(self, forKeyPath: #keyPath(WKWebView.estimatedProgress), options: .new, context: nil)

    }
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "estimatedProgress" {
            progressView.progress = Float(webView.estimatedProgress)
        }
    }

    @objc func openTapped() {
        let ac = UIAlertController(title: "Enter URL or search term", message: nil, preferredStyle: .alert)
//        ac.addAction(UIAlertAction(title: "apple.com", style: .default, handler: openPage))
//        ac.addAction(UIAlertAction(title: "hackingwithswift.com", style: .default, handler: openPage))
        ac.addTextField { (textField) in
            textField.text = ""
        }

        // 3. Grab the value from the text field, and print it when the user clicks OK.
        ac.addAction(UIAlertAction(title: "OK", style: .default, handler: { [weak ac] (_) in
            let textField = ac!.textFields![0]
            self.loadWebsite(partial: textField.text!)
        }))

        
        ac.addAction(UIAlertAction(title: "Paste and go", style: .default, handler: { [weak ac] (_) in
            let pasted = UIPasteboard.general.string
            if (pasted != nil) {
                self.loadWebsite(partial: pasted!)
            }
        }))
        ac.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        ac.popoverPresentationController?.barButtonItem = self.navigationItem.rightBarButtonItem
        present(ac, animated: true)
    }
    
    func stripProtocol(url: String) -> String? {
        do {
            let regex = try NSRegularExpression(pattern: "https\\:\\/\\/", options: NSRegularExpression.Options.caseInsensitive)
            let range = NSMakeRange(0, url.count)
            return regex.stringByReplacingMatches(in: url, options: [], range: range, withTemplate: "")
        } catch {
            return nil
        }
    }
    
    func errorDialog(message: String) {
        let alert = UIAlertController(title: "Error", message: message, preferredStyle: .alert)

        alert.addAction(UIAlertAction(title: "Okay", style: .default, handler: nil))

        self.present(alert, animated: true)
    }
    
    func searchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "google.com"
        components.path = "/search"

        let queryItemQuery = URLQueryItem(name: "q", value: query)

        components.queryItems = [queryItemQuery]
        
        return components.url
    }
    
    func validUrl(url: URL) -> Bool {
        let regex = NSRegularExpression("\\w+\\.\\w+")
        return regex.matches(url.absoluteString)
    }
    
    func loadWebsite(partial: String) {
        let trimmed = partial.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = stripProtocol(url: trimmed)
        
        var url = cleaned != nil ? URL(string: "https://" +  cleaned!) : nil
        
        print(url, "valid:", validUrl(url: url!))
        if (url == nil || !validUrl(url: url!)) {
            url = searchURL(query: trimmed)
        }
 
        if (url != nil) {
            print("going", url)
            self.webView.load(URLRequest(url: url!))
        } else {
            print("failing", url)
            errorDialog(message: "The address you entered was not valid")
        }
    }
     
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        title = webView.title
    }
    func receiveMidiMessageFromInput(message: MIDIPacket, from: MIDIInput) {
        let serializedData = try! JSONSerialization.data(withJSONObject: ["type": "midimessage", "portID": from.string(for: MIDIObject.Property.uniqueID), "data": message.bytes.map { Int($0) }])
        print("receiveMidiMessageFromInput sending json", String(data: serializedData, encoding: String.Encoding.utf8) ?? "");
        webView.evaluateJavaScript("window.__WebMidiBrowser.receiveMessage(`\(String(data: serializedData, encoding: String.Encoding.utf8) ?? "")`)")  { (result, error) in
            if error != nil {
                print(error!)
            }
        }
    }
     
    
    func updateDeviceMIDIState(object: MIDIObject, objType: String) {
        let portProperties = [
            "id": String(try! object.integer(for: MIDIObject.Property.uniqueID)),
            "manufacturer": try! object.string(for: MIDIObject.Property.manufacturer),
            "name": try! object.string(for: MIDIObject.Property.name),
            "type": objType,
            "version": "1", // try! port.string(for: MIDIObject.Property.driverVersion),
            "state": "connected", //try! port.string(for: MIDIObject.Property.offline),
            "connection": "open",
            
        ]
        let serializedData = try! JSONSerialization.data(withJSONObject: ["type": "statechange", "properties": portProperties])
        print("updateDeviceMIDIState sending json", String(data: serializedData, encoding: String.Encoding.utf8) ?? "");
        webView.evaluateJavaScript("window.__WebMidiBrowser.receiveMessage(`\(String(data: serializedData, encoding: String.Encoding.utf8) ?? "")`)")  { (result, error) in
            if error != nil {
                print(error!)
            }
        }
    }
}

    
extension ViewController: WKScriptMessageHandler {
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let dict = message.body as? [String : AnyObject] else {
            print("invalid message")
            return
        }
 
        
        switch (dict["type"] as! String) {
            case  "connect":
                print("got connect message")
                for device in MIDIDevice.all {
                    print("init device", device.name)
                    for destination in device.destinations {
                        updateDeviceMIDIState(object: destination, objType: "output")
                    }
                    for source in device.sources {
                        updateDeviceMIDIState(object: source, objType: "input")
                    }
                }
            case  "midioutput":
                print("midioutput", dict["portID"] as! String, dict["data"] as Any)
                return
            case "log":
                print(dict["value"] as! String)
                return
            default:
                print("unknown message type", dict["type"] as! String)
                return
        }
    }
}
