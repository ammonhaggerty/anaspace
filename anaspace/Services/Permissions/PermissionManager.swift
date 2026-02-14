import AVFoundation
import CoreLocation
import Foundation
import MusicKit
import Speech
import UserNotifications

// MARK: - Permission State

enum PermissionState: String, Codable, Sendable {
    case undetermined
    case granted
    case denied
}

// MARK: - CLLocationManager Delegate Proxy

private final class CLLocationDelegateProxy: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        continuation?.resume(returning: manager.authorizationStatus)
        continuation = nil
    }
}

// MARK: - Permission Manager

@Observable @MainActor
final class PermissionManager {

    // MARK: Properties

    var microphone: PermissionState = .undetermined
    var location: PermissionState = .undetermined
    var speechRecognition: PermissionState = .undetermined
    var notifications: PermissionState = .undetermined
    var appleMusic: PermissionState = .undetermined

    var corePermissionsGranted: Bool {
        microphone == .granted && location == .granted && speechRecognition == .granted
    }

    // MARK: Private

    private let locationManager = CLLocationManager()
    private let locationDelegate = CLLocationDelegateProxy()

    init() {
        locationManager.delegate = locationDelegate
    }

    // MARK: Refresh

    func refreshAll() async {
        microphone = mapRecordPermission(AVAudioApplication.shared.recordPermission)
        location = mapCLAuthorizationStatus(locationManager.authorizationStatus)
        speechRecognition = mapSpeechAuthorizationStatus(SFSpeechRecognizer.authorizationStatus())
        appleMusic = mapMusicAuthorizationStatus(MusicAuthorization.currentStatus)

        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notifications = mapNotificationAuthorizationStatus(settings.authorizationStatus)
    }

    // MARK: Request Methods

    @discardableResult
    func requestMicrophone() async -> PermissionState {
        if await AVAudioApplication.requestRecordPermission() {
            microphone = .granted
        } else {
            microphone = .denied
        }
        return microphone
    }

    @discardableResult
    func requestLocation() async -> PermissionState {
        let currentStatus = locationManager.authorizationStatus
        guard currentStatus == .notDetermined else {
            location = mapCLAuthorizationStatus(currentStatus)
            return location
        }

        let status = await withCheckedContinuation { (continuation: CheckedContinuation<CLAuthorizationStatus, Never>) in
            locationDelegate.continuation = continuation
            locationManager.requestWhenInUseAuthorization()
        }
        location = mapCLAuthorizationStatus(status)
        return location
    }

    @discardableResult
    func requestSpeechRecognition() async -> PermissionState {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<SFSpeechRecognizerAuthorizationStatus, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        speechRecognition = mapSpeechAuthorizationStatus(status)
        return speechRecognition
    }

    @discardableResult
    func requestNotifications() async -> PermissionState {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            notifications = granted ? .granted : .denied
        } catch {
            notifications = .denied
        }
        return notifications
    }

    @discardableResult
    func requestAppleMusic() async -> PermissionState {
        let status = await MusicAuthorization.request()
        appleMusic = mapMusicAuthorizationStatus(status)
        return appleMusic
    }

    // MARK: - Private Mapping Functions

    private func mapRecordPermission(_ permission: AVAudioApplication.recordPermission) -> PermissionState {
        switch permission {
        case .undetermined: .undetermined
        case .denied: .denied
        case .granted: .granted
        @unknown default: .undetermined
        }
    }

    private func mapCLAuthorizationStatus(_ status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: .undetermined
        case .restricted, .denied: .denied
        case .authorizedAlways, .authorizedWhenInUse: .granted
        @unknown default: .undetermined
        }
    }

    private func mapSpeechAuthorizationStatus(_ status: SFSpeechRecognizerAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: .undetermined
        case .denied, .restricted: .denied
        case .authorized: .granted
        @unknown default: .undetermined
        }
    }

    private func mapNotificationAuthorizationStatus(_ status: UNAuthorizationStatus) -> PermissionState {
        switch status {
        case .notDetermined: .undetermined
        case .denied: .denied
        case .authorized, .provisional, .ephemeral: .granted
        @unknown default: .undetermined
        }
    }

    private func mapMusicAuthorizationStatus(_ status: MusicAuthorization.Status) -> PermissionState {
        switch status {
        case .notDetermined: .undetermined
        case .denied, .restricted: .denied
        case .authorized: .granted
        @unknown default: .undetermined
        }
    }
}
