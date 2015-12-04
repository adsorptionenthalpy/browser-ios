/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import WebKit
import Shared

protocol ContextMenuHelperDelegate: class {
    func contextMenuHelper(contextMenuHelper: ContextMenuHelper, didLongPressElements elements: ContextMenuHelper.Elements, gestureRecognizer: UILongPressGestureRecognizer)
}

class ContextMenuHelper: NSObject, BrowserHelper, UIGestureRecognizerDelegate {
    private weak var browser: Browser?
    weak var delegate: ContextMenuHelperDelegate?
    private let gestureRecognizer = UILongPressGestureRecognizer()
    private var selectionGestureRecognizer = WeakList<UIGestureRecognizer>()

    struct Elements {
        let link: NSURL?
        let image: NSURL?
    }

    class func name() -> String {
        return "ContextMenuHelper"
    }

    /// On iOS <9, clicking an element with VoiceOver fires touchstart, but not touchend, causing the context
    /// menu to appear when it shouldn't (filed as rdar://22256909). As a workaround, disable the custom
    /// context menu for VoiceOver users on iOS <9.
    private var showCustomContextMenu: Bool {
        return NSProcessInfo.processInfo().operatingSystemVersion.majorVersion >= 9 || !UIAccessibilityIsVoiceOverRunning()
    }

    required init(browser: Browser) {
        super.init()

#if BRAVE // shutting this off to investigate scrolling problems
 return
#endif

        self.browser = browser

        let path = NSBundle.mainBundle().pathForResource("ContextMenu", ofType: "js")!
        let source = try! NSString(contentsOfFile: path, encoding: NSUTF8StringEncoding) as String
        let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.AtDocumentEnd, forMainFrameOnly: false)
        browser.webView!.configuration.userContentController.addUserScript(userScript)

        // Add a gesture recognizer that disables the built-in context menu gesture recognizer.
        gestureRecognizer.delegate = self
        browser.webView!.addGestureRecognizer(gestureRecognizer)
    }

    func scriptMessageHandlerName() -> String? {
        return "contextMenuMessageHandler"
    }

    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if !showCustomContextMenu {
            return
        }

        guard let data = message.body as? [String: AnyObject] else { return }

        // On sites where <a> elements have child text elements, the text selection delegate can be triggered
        // when we show a context menu. To prevent this, cancel the text selection delegate if we know the
        // user is long-pressing a link.
        if let handled = data["handled"] as? Bool where handled {
            // Setting `enabled = false` cancels the current gesture for this recognizer.
          for item in selectionGestureRecognizer {
            item.enabled = false
            item.enabled = true
          }
        }

        var linkURL: NSURL?
        if let urlString = data["link"] as? String {
            linkURL = NSURL(string: urlString.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLAllowedCharacterSet())!)
        }

        var imageURL: NSURL?
        if let urlString = data["image"] as? String {
            imageURL = NSURL(string: urlString.stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLAllowedCharacterSet())!)
        }

        if linkURL != nil || imageURL != nil {
            let elements = Elements(link: linkURL, image: imageURL)
            delegate?.contextMenuHelper(self, didLongPressElements: elements, gestureRecognizer: gestureRecognizer)
        }
    }

    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWithGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
#if BRAVE
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailByGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
      if otherGestureRecognizer is UILongPressGestureRecognizer {
        selectionGestureRecognizer.insert(otherGestureRecognizer)
      }
      return false
    }
#else
    func gestureRecognizer(gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailByGestureRecognizer otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Hack to detect the built-in text selection gesture recognizer.
        if let otherDelegate = otherGestureRecognizer.delegate where String(otherDelegate).contains("_UIKeyboardBasedNonEditableTextSelectionGestureController") {
            selectionGestureRecognizer = otherGestureRecognizer
        }

        // Hack to detect the built-in context menu gesture recognizer.
        return otherGestureRecognizer is UILongPressGestureRecognizer && otherGestureRecognizer.delegate?.description.rangeOfString("WKContentView") != nil
    }
#endif
    func gestureRecognizerShouldBegin(gestureRecognizer: UIGestureRecognizer) -> Bool {
        return showCustomContextMenu
    }
}