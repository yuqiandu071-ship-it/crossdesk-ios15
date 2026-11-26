import SwiftUI
import UIKit

final class CrossDeskAppDelegate: NSObject, UIApplicationDelegate {
    static var supportedOrientations: UIInterfaceOrientationMask = .portrait

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
                // iOS 15 没有 requestGeometryUpdate，用 KVC 强制旋转 + 通知系统重算
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

    var body: some Scene {
        WindowGroup {
            ContentView(session: session)
        }
    }
}
