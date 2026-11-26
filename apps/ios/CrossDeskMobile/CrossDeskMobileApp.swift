import SwiftUI
import UIKit
import Darwin
import Foundation

private var launchTraceFD: Int32 = -1

func launchTraceWrite(_ text: String) {
    guard launchTraceFD >= 0 else { return }
    let line = text + "\n"
    line.withCString { pointer in
        _ = Darwin.write(launchTraceFD, pointer, strlen(pointer))
    }
}

/// Appends launch breadcrumbs to Documents/crossdesk-launch.log.
/// The file is visible in the Files app because UIFileSharingEnabled is set.
enum LaunchTrace {
    static let filePath: String = {
        let manager = FileManager.default
        let dir = manager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return dir.appendingPathComponent("crossdesk-launch.log").path
    }()

    static func install() {
        launchTraceFD = open(filePath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        write("=== crossdesk launch trace v2 (\(Date().timeIntervalSince1970)) ===")
        write("ios=\(UIDevice.current.systemVersion) model=\(UIDevice.current.model)")
        write("bundle=\(Bundle.main.bundleIdentifier ?? "-") minos=\(Bundle.main.infoDictionary?["MinimumOSVersion"] ?? "-")")
    }

    static func write(_ text: String) {
        launchTraceWrite(text)
    }

    static func log(_ tag: String) {
        let thread = Thread.isMainThread ? "main" : "bg"
        launchTraceWrite("[\(Date().timeIntervalSince1970)] \(tag) thread=\(thread)")
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
