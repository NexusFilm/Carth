import Foundation
import Observation
import Supabase
import UIKit
import UserNotifications

@MainActor
@Observable
final class PushNotificationService {
    static let shared = PushNotificationService()

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var registrationMessage: String?
    private(set) var testAlertMessage: String?
    private(set) var testAlertFailed = false
    private(set) var isSendingTestAlert = false
    private(set) var bannersEnabled = false
    private var isRefreshingAPNsAfterTestFailure = false
    private var signedInUserID: String?
    private var deviceToken: String? {
        UserDefaults.standard.string(forKey: "catharsia.apnsDeviceToken")
    }
    private var apnsEnvironment: String? {
        UserDefaults.standard.string(forKey: "catharsia.apnsEnvironment")
    }

    func setSignedInUser(_ userID: String?) {
        guard signedInUserID != userID else { return }
        signedInUserID = userID
        guard userID != nil else { return }
        Task { await refreshAuthorizationStatus() }
    }

    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        // alertSetting only says iOS permits alerts. alertStyle also reflects
        // whether iOS will actually present them as banners while unlocked.
        bannersEnabled = settings.alertSetting == .enabled && settings.alertStyle == .banner
        if settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional {
            UIApplication.shared.registerForRemoteNotifications()
            await registerDeviceIfReady()
        }
    }

    func requestAuthorization() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshAuthorizationStatus()
            if !granted {
                registrationMessage = "Push alerts are off. You can turn them on in iPhone Settings."
            }
        } catch {
            registrationMessage = "Push alerts couldn’t be enabled. You can try again in iPhone Settings."
        }
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    func sendTestAlert() async {
        guard signedInUserID != nil else {
            testAlertMessage = "Sign in to send a test alert."
            testAlertFailed = true
            return
        }
        testAlertMessage = nil
        testAlertFailed = false
        isSendingTestAlert = true
        defer { isSendingTestAlert = false }
        do {
            let response: PushActionResponse = try await SupabaseServices.shared.client.functions.invoke(
                "catharsia-push",
                options: FunctionInvokeOptions(method: .post, body: PushActionRequest(action: "test"))
            )
            if response.push == "sent" {
                testAlertMessage = "Test alert sent. Check your iPhone notifications."
                testAlertFailed = false
            } else if response.push == "no_registered_device" {
                testAlertMessage = "This iPhone isn’t registered yet. Try again in a moment."
                testAlertFailed = true
            } else if response.push == "bad_device_token" {
                isRefreshingAPNsAfterTestFailure = true
                testAlertMessage = "Apple rejected the saved device token. Refreshing this iPhone’s push registration…"
                testAlertFailed = true
                UIApplication.shared.registerForRemoteNotifications()
            } else if response.push == "environment_corrected" {
                testAlertMessage = "Push environment updated. Send another test alert to confirm delivery."
                testAlertFailed = true
            } else if response.push == "apns_rate_limited" {
                testAlertMessage = "Apple is limiting repeated tests. Wait 20 minutes before trying again."
                testAlertFailed = true
            } else {
                testAlertMessage = "Supabase couldn’t deliver a test alert. Check APNs delivery settings."
                testAlertFailed = true
            }
        } catch {
            testAlertMessage = "Supabase couldn’t deliver a test alert. Please try again."
            testAlertFailed = true
        }
    }

    func didRegister(deviceToken data: Data) {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: "catharsia.apnsDeviceToken")
        #if DEBUG
        UserDefaults.standard.set("sandbox", forKey: "catharsia.apnsEnvironment")
        #else
        UserDefaults.standard.set("production", forKey: "catharsia.apnsEnvironment")
        #endif
        Task {
            await registerDeviceIfReady()
            guard isRefreshingAPNsAfterTestFailure else { return }
            isRefreshingAPNsAfterTestFailure = false
            if registrationMessage == nil {
                testAlertMessage = "This iPhone registered again. Send another test alert to confirm delivery."
                testAlertFailed = false
            } else {
                testAlertMessage = "This iPhone couldn’t refresh its push registration. Try again after reopening Catharsia."
                testAlertFailed = true
            }
        }
    }

    func didFailToRegister() {
        registrationMessage = "Push alerts aren’t available in this signed build. In-app notifications still work."
        if isRefreshingAPNsAfterTestFailure {
            isRefreshingAPNsAfterTestFailure = false
            testAlertMessage = "This iPhone couldn’t refresh its push registration. Check notification access in Settings."
            testAlertFailed = true
        }
    }

    func unregisterCurrentDevice() async {
        guard signedInUserID != nil, let deviceToken, let apnsEnvironment else { return }
        do {
            let request = PushActionRequest(action: "unregister", deviceToken: deviceToken, apnsEnvironment: apnsEnvironment)
            let _: PushActionResponse = try await SupabaseServices.shared.client.functions.invoke(
                "catharsia-push",
                options: FunctionInvokeOptions(method: .post, body: request)
            )
            UserDefaults.standard.removeObject(forKey: "catharsia.apnsDeviceToken")
            UserDefaults.standard.removeObject(forKey: "catharsia.apnsEnvironment")
        } catch {
            registrationMessage = "This phone’s push registration couldn’t be removed yet."
        }
    }

    private func registerDeviceIfReady() async {
        guard signedInUserID != nil,
              authorizationStatus == .authorized || authorizationStatus == .provisional,
              let deviceToken,
              let apnsEnvironment,
              SupabaseServices.shared.configuration.isConfigured else { return }

        do {
            let request = PushActionRequest(
                action: "register",
                deviceToken: deviceToken,
                apnsEnvironment: apnsEnvironment,
                appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
                buildNumber: Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            )
            let _: PushActionResponse = try await SupabaseServices.shared.client.functions.invoke(
                "catharsia-push",
                options: FunctionInvokeOptions(method: .post, body: request)
            )
            registrationMessage = nil
        } catch {
            registrationMessage = "Push alerts couldn’t connect to Supabase. In-app notifications will still appear."
        }
    }
}

@MainActor
final class CatharsiaAppDelegate: NSObject, UIApplicationDelegate, @preconcurrency UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationService.shared.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationService.shared.didFailToRegister()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let content = notification.request.content
        var bannerInfo: [String: String] = [
            "title": content.title,
            "body": content.body
        ]
        if let destination = content.userInfo["destination"] as? String {
            bannerInfo["destination"] = destination
        }
        NotificationCenter.default.post(
            name: .catharsiaShowInAppNotificationBanner,
            object: nil,
            userInfo: bannerInfo
        )
        return [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo
        if let rawDestination = userInfo["destination"] as? String,
           CatharsiaAnnouncementDestination(rawValue: rawDestination) != nil {
            NotificationCenter.default.post(
                name: .catharsiaNavigateToTab,
                object: nil,
                userInfo: ["destination": rawDestination]
            )
            return
        }
        NotificationCenter.default.post(name: .catharsiaOpenNotificationCenter, object: nil)
    }
}

extension Notification.Name {
    static let catharsiaOpenNotificationCenter = Notification.Name("catharsia.openNotificationCenter")
    static let catharsiaPresentNotificationCenter = Notification.Name("catharsia.presentNotificationCenter")
    static let catharsiaNavigateToTab = Notification.Name("catharsia.navigateToTab")
    static let catharsiaShowInAppNotificationBanner = Notification.Name("catharsia.showInAppNotificationBanner")
}

private struct PushActionRequest: Encodable, Sendable {
    let action: String
    var deviceToken: String? = nil
    var apnsEnvironment: String? = nil
    var appVersion: String? = nil
    var buildNumber: String? = nil
    var entityID: String? = nil

    enum CodingKeys: String, CodingKey {
        case action
        case deviceToken = "device_token"
        case apnsEnvironment = "apns_environment"
        case appVersion = "app_version"
        case buildNumber = "build_number"
        case entityID = "entity_id"
    }
}

private struct PushActionResponse: Decodable, Sendable {
    let ok: Bool?
    let push: String?
}
