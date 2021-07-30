import Combine
import UIKit
import MapboxNavigation
import MapboxCoreNavigation
import CarPlay
import MultipeerKit
import MapboxNavigationRemoteKit
import MapboxNavigationHistoryKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {
    weak var currentAppRootViewController: ViewController?
    
    var window: UIWindow?
    
    @available(iOS 12.0, *)
    lazy var carPlayManager: CarPlayManager = CarPlayManager()
    
    @available(iOS 12.0, *)
    lazy var carPlaySearchController: CarPlaySearchController = CarPlaySearchController()

    // `CLLocationManager` instance, which is going to be used to create a location, which is used as a
    // hint when looking up the specified address in `CarPlaySearchController`.
    static let coarseLocationManager: CLLocationManager = {
        let coarseLocationManager = CLLocationManager()
        coarseLocationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        return coarseLocationManager
    }()
    
    @available(iOS 12.0, *)
    lazy var recentSearchItems: [CPListItem]? = []
    var recentItems: [RecentItem] = RecentItem.loadDefaults()
    var recentSearchText: String? = ""

    private var subscriptions: [AnyCancellable] = []
    
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        if isRunningTests() {
            if window == nil {
                window = UIWindow(frame: UIScreen.main.bounds)
            }
            window?.rootViewController = UIViewController()
        }
        PassiveLocationManager.historyDirectoryURL = Current.historyUrl
        listMapboxFrameworks()
        Current.setupRemoteCli()

        Current.actions.listHistoryFiles
            .receive(on: DispatchQueue.global())
            .sink { peerPayload in
                do {
                    let historyFileUrls = try FileManager.default
                        .contentsOfDirectory(at: Current.historyUrl,
                                             includingPropertiesForKeys: [.creationDateKey],
                                             options: [.skipsHiddenFiles])
                    Current.transceiver.send(HistoryFilesResponse(files: historyFileUrls.map(HistoryFile.init(_:))),
                                             to: [peerPayload.sender])
                }
                catch {
                    print(error)
                }
            }
            .store(in: &subscriptions)

        Current.actions.downloadHistoryFile
            .receive(on: DispatchQueue.global())
            .sink { peerPayload in
                do {
                    let fileData = try Data(contentsOf: URL(fileURLWithPath: peerPayload.payload.historyFile.path))
                    let response = DownloadHistoryFileResponse(name: peerPayload.payload.historyFile.name,
                                                               data: fileData)
                    Current.transceiver.send(response, to: [peerPayload.sender])
                }
                catch {
                    print(error)
                }
            }
            .store(in: &subscriptions)

        Current.actions.downloadGpxHistoryFile
            .receive(on: DispatchQueue.global())
            .sink { peerPayload in
                let path = peerPayload.payload.historyFile.path
                guard FileManager.default.fileExists(atPath: path) else { return}
                let gpxString = Parser.parseHistory(at: path, with: .gpx)
                guard let fileData = gpxString.data(using: .utf8) else { return }
                let name = ((peerPayload.payload.historyFile.name as NSString).deletingPathExtension as NSString).appendingPathExtension("gpx") ?? "error.gpx"
                let response = DownloadGpxHistoryFileResponse(name: name, data: fileData)
                Current.transceiver.send(response, to: [peerPayload.sender])
            }
            .store(in: &subscriptions)
        
        return true
    }

    private func isRunningTests() -> Bool {
        return NSClassFromString("XCTestCase") != nil
    }
    
    private func listMapboxFrameworks() {
        NSLog("Versions of linked Mapbox frameworks:")
        
        for framework in Bundle.allFrameworks {
            if let bundleIdentifier = framework.bundleIdentifier, bundleIdentifier.contains("mapbox") {
                let version = "CFBundleShortVersionString"
                NSLog("\(bundleIdentifier): \(framework.infoDictionary?[version] ?? "Unknown version")")
            }
        }
    }
}

// MARK: - UIWindowSceneDelegate methods

@available(iOS 13.0, *)
extension AppDelegate: UIWindowSceneDelegate {

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        if connectingSceneSession.role == .carTemplateApplication {
            return UISceneConfiguration(name: "ExampleCarPlayApplicationConfiguration", sessionRole: connectingSceneSession.role)
        }
        
        return UISceneConfiguration(name: "ExampleAppConfiguration", sessionRole: connectingSceneSession.role)
    }
}
