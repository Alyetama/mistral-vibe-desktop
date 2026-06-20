import AppKit
import WebKit

// MARK: - Configuration

enum Config {
    static let appName = "Vibe"
    static let homeURL = URL(string: "https://chat.mistral.ai/")!
    // Keep navigation inside the app for these hosts; everything else opens in
    // the user's default browser.
    static let internalHosts: Set<String> = [
        "chat.mistral.ai",
        "mistral.ai",
        "auth.mistral.ai",
        // Auth providers used by Mistral's login flow:
        "accounts.google.com",
        "appleid.apple.com",
        "github.com",
        "login.microsoftonline.com"
    ]
}

// MARK: - Web View Controller

final class WebViewController: NSViewController, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {

    private(set) var webView: WKWebView!

    override func loadView() {
        let config = WKWebViewConfiguration()
        // Persistent store => cookies / localStorage survive relaunch, so the
        // user stays logged in.
        config.websiteDataStore = .default()
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        if #available(macOS 11.0, *) {
            config.defaultWebpagePreferences.allowsContentJavaScript = true
        }
        // Skip the Safe Browsing network lookup WebKit does on each navigation —
        // we only ever load Mistral, and it adds latency to every page change.
        config.preferences.isFraudulentWebsiteWarningEnabled = false

        // A concrete frame here sets the view's fitting size; otherwise the
        // window (sized from its contentViewController) collapses to 1×1.
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1100, height: 760),
                            configuration: config)
        webView.autoresizingMask = [.width, .height]
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        if #available(macOS 13.3, *) {
            webView.isInspectable = true
        }
        self.view = webView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.load(URLRequest(url: Config.homeURL))
    }

    func reload() { webView.reload() }
    func goHome() { webView.load(URLRequest(url: Config.homeURL)) }
    func goBack() { if webView.canGoBack { webView.goBack() } }
    func goForward() { if webView.canGoForward { webView.goForward() } }

    private func isInternal(_ url: URL) -> Bool {
        guard let host = url.host else { return true } // about:blank etc.
        return Config.internalHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 preferences: WKWebpagePreferences,
                 decisionHandler: @escaping (WKNavigationActionPolicy, WKWebpagePreferences) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow, preferences); return
        }

        // Only redirect to the external browser for explicit user clicks on
        // non-internal links. Let downloads, redirects, subframes stay in-app.
        if navigationAction.navigationType == .linkActivated,
           navigationAction.targetFrame?.isMainFrame == true,
           !isInternal(url),
           let scheme = url.scheme, scheme == "http" || scheme == "https" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel, preferences)
            return
        }
        decisionHandler(.allow, preferences)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download) // hand off to the download delegate
        }
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: WKUIDelegate — handle target="_blank" / window.open

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url {
            if isInternal(url) {
                webView.load(URLRequest(url: url))
            } else {
                NSWorkspace.shared.open(url)
            }
        }
        return nil
    }

    // File picker for uploads (attaching files in chat)
    func webView(_ webView: WKWebView,
                 runOpenPanelWith parameters: WKOpenPanelParameters,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.canChooseFiles = true
        panel.begin { result in
            completionHandler(result == .OK ? panel.urls : nil)
        }
    }

    // MARK: WKDownloadDelegate

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var dest = downloads.appendingPathComponent(suggestedFilename)
        var i = 1
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        while FileManager.default.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            dest = downloads.appendingPathComponent(name)
            i += 1
        }
        completionHandler(dest)
    }

    func download(_ download: WKDownload, didFailWithError error: Error,
                  resumeData: Data?) {
        NSSound.beep()
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let url = download.progress.fileURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var controller: WebViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller = WebViewController()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = Config.appName
        window.titlebarAppearsTransparent = false
        window.contentViewController = controller
        window.setFrameAutosaveName("MistralMainWindow") // restores size/position
        // Guard against a previously-saved degenerate frame: if the restored
        // size is too small to be usable, fall back to the default and center.
        if window.frame.width < 480 || window.frame.height < 360 {
            window.setContentSize(NSSize(width: 1100, height: 760))
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.webView) // first click hits the page, not focus

        buildMenu()
        NSApp.activate(ignoringOtherApps: true)
    }

    // Keep the app alive when the window is closed (it's only hidden, see below).
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Clicking the red close button hides the window instead of destroying it,
    // so the web view (and your session/page state) stays alive. The app keeps
    // running in the Dock; reopen it from the Dock icon. Quit with ⌘Q.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // Re-show the window when the Dock icon is clicked.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }

    // MARK: Menu

    private func buildMenu() {
        let mainMenu = NSMenu()

        // App menu
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "About \(Config.appName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(Config.appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit \(Config.appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        // Edit menu (gives Cmd+C/V/X/A/Z standard behavior)
        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        // View menu
        let viewMenuItem = NSMenuItem()
        mainMenu.addItem(viewMenuItem)
        let viewMenu = NSMenu(title: "View")
        viewMenuItem.submenu = viewMenu
        viewMenu.addItem(withTitle: "Reload", action: #selector(reload), keyEquivalent: "r")
        viewMenu.addItem(withTitle: "Home", action: #selector(goHome), keyEquivalent: "0")
        viewMenu.addItem(.separator())
        let back = viewMenu.addItem(withTitle: "Back", action: #selector(goBack), keyEquivalent: "[")
        back.keyEquivalentModifierMask = [.command]
        let fwd = viewMenu.addItem(withTitle: "Forward", action: #selector(goForward), keyEquivalent: "]")
        fwd.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(.separator())
        let fullScreen = viewMenu.addItem(withTitle: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]

        // Window menu
        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func reload() { controller.reload() }
    @objc private func goHome() { controller.goHome() }
    @objc private func goBack() { controller.goBack() }
    @objc private func goForward() { controller.goForward() }
}

// MARK: - Entry point

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
