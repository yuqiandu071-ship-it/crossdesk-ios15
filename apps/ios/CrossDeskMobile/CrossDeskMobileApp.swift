import SwiftUI
import UIKit
import Darwin

/// Writes launch breadcrumbs to Documents/crossdesk-launch.log so a crash on an
/// older iOS build can be diagnosed from the Files app without a Mac.
private var launchTraceFD: Int32 = -1

enum LaunchTrace {
    private static let path: String = {
        let fm = FileManager.default
        let dir = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return dir.appendingPathComponent("crossdesk-launch.log").path
    }()

    static func install() {
        launchTraceFD = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        write("=== crossdesk launch trace v1 ===")
        write("ios=\(UIDevice.current.systemVersion) model=\(UIDevice.current.model) name=\(UIDevice.current.name)")
        write("bundle=\(Bundle.main.bundleIdentifier ?? "-") minos=\(Bundle.main.infoDictionary?["MinimumOSVersion"] ?? "-")")
        NSSetUncaughtExceptionHandler { exception in
            let frames = exception.callStackSymbols.joined(separator: "\n")
            write("UNCAUGHT \(exception.name.rawValue): \(exception.reason ?? "-")\n\(frames)")
        }
        for sig in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] {
            signal(sig) { received in
                let frames = Thread.callStackSymbols.joined(separator: "\n")
                write("\nSIGNAL \(received)\n\(frames)")
                Darwin.close(launchTraceFD)
                exit(128 + received)
            }
        }
    }

    static func log(_ tag: String) {
        let thread = Thread.isMainThread ? "main" : (Thread.current.name ?? "bg")
        write("[\(Date().timeIntervalSince1970)] \(tag) thread=\(thread)")
    }

    static func write(_ text: String) {
        guard launchTraceFD >= 0 else { return }
        let line = text + "\n"
        line.withCString { buffer in
            _ = Darwin.write(launchTraceFD, buffer, strlen(buffer))
        }
    }
}

final class CrossDeskAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        LaunchTrace.log("appDelegate.didFinishLaunching")
        return true
    }

    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?)
        -> UIInterfaceOrientationMask {
        Self.supportedOrientations
    }
}

enum AppOrientation {
    static func update(to orientations: UIInterfaceOrientationMask) {
        DispatchQueue.main.async {
            CrossDeskAppDelegate.supportedOrientations = orientations

            if #available(iOS 16.0, *) {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    scene.windows.forEach {
                        $0.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                    }
                    scene.requestGeometryUpdate(
                        .iOS(interfaceOrientations: orientations)
                    ) { error in
                        NSLog("CrossDesk orientation update failed: %@", error.localizedDescription)
                    }
                }
            } else {
                // iOS 15 has no requestGeometryUpdate: force the orientation through KVC
                // and ask UIKit to recompute the supported interface orientations.
                if let target = singleOrientation(for: orientations) {
                    UIDevice.current.setValue(target.rawValue, forKey: "orientation")
                }
                UIViewController.attemptRotationToDeviceOrientation()
            }
        }
    }

    private static func singleOrientation(for mask: UIInterfaceOrientationMask) -> UIInterfaceOrientation? {
        switch mask {
        case .portrait: return .portrait
        case .portraitUpsideDown: return .portraitUpsideDown
        case .landscapeLeft: return .landscapeLeft
        case .landscapeRight: return .landscapeRight
        default: return nil
        }
    }
}

@main
struct CrossDeskMobileApp: App {
    @UIApplicationDelegateAdaptor(CrossDeskAppDelegate.self) private var appDelegate
    @StateObject private var session = RemoteSessionModel()

    init() {
        LaunchTrace.install()
        LaunchTrace.log("CrossDeskMobileApp.init")
    }

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
                .onAppear { LaunchTrace.log("ContentView.onAppear") }
        }
    }
}
