import AVFoundation
import UIKit

enum CallMicrophoneAccess: Equatable {
    case granted
    /// The prompt was shown just now and declined.
    case refused
    /// Declined earlier; only Settings can change it.
    case denied
    /// Never asked, and the prompt policy didn't allow asking now.
    case deferred
}

enum MicrophonePromptPolicy {
    /// Answering must not await a prompt that can't appear while the app isn't active.
    case whenActive
    /// Unmuting during a live call asks whatever the app state.
    case always
}

protocol CallPermissionsServicing: AnyObject {
    var isMicrophoneGranted: Bool { get }

    /// Only an explicit denial: iOS shows no Microphone switch in Settings until the app has asked once.
    var isMicrophoneDenied: Bool { get }

    func resolveMicrophoneAccess(prompting policy: MicrophonePromptPolicy) async -> CallMicrophoneAccess

    func requestCameraAccessIfNeeded(for callType: ChatCallType) async

    func ensurePermissions(for callType: ChatCallType) async -> Bool
}

final class CallPermissionsService {
    private let applicationStateProvider: @MainActor () -> UIApplication.State
    private let recordPermissionProvider: () -> AVAudioApplication.recordPermission
    private let recordPermissionRequester: () async -> Bool

    init(
        applicationStateProvider: @escaping @MainActor () -> UIApplication.State = {
            UIApplication.shared.applicationState
        },
        recordPermissionProvider: @escaping () -> AVAudioApplication.recordPermission = {
            AVAudioApplication.shared.recordPermission
        },
        recordPermissionRequester: @escaping () async -> Bool = {
            await AVAudioApplication.requestRecordPermission()
        }
    ) {
        self.applicationStateProvider = applicationStateProvider
        self.recordPermissionProvider = recordPermissionProvider
        self.recordPermissionRequester = recordPermissionRequester
    }
}

private extension CallPermissionsService {
    // Awaiting a system prompt the inactive app can't present stalls the caller instead of asking.
    @MainActor
    var canPresentPermissionPrompt: Bool {
        applicationStateProvider() == .active
    }

    func canPrompt(with policy: MicrophonePromptPolicy) async -> Bool {
        switch policy {
        case .always:
            true
        case .whenActive:
            await canPresentPermissionPrompt
        }
    }
}

extension CallPermissionsService: CallPermissionsServicing {
    var isMicrophoneGranted: Bool {
        recordPermissionProvider() == .granted
    }

    var isMicrophoneDenied: Bool {
        recordPermissionProvider() == .denied
    }

    func resolveMicrophoneAccess(prompting policy: MicrophonePromptPolicy) async -> CallMicrophoneAccess {
        switch recordPermissionProvider() {
        case .granted:
            return .granted
        case .denied:
            return .denied
        case .undetermined:
            guard await canPrompt(with: policy) else {
                return .deferred
            }

            return await recordPermissionRequester() ? .granted : .refused
        @unknown default:
            return .denied
        }
    }

    func requestCameraAccessIfNeeded(for callType: ChatCallType) async {
        guard
            callType == .video,
            AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined,
            await canPresentPermissionPrompt
        else {
            return
        }

        _ = await AVCaptureDevice.requestAccess(for: .video)
    }

    func ensurePermissions(for callType: ChatCallType) async -> Bool {
        guard await resolveMicrophoneAccess(prompting: .whenActive) == .granted else {
            return false
        }

        // Camera denial is tolerated: the call degrades to audio-only,
        // so only the microphone is a hard requirement.
        await requestCameraAccessIfNeeded(for: callType)

        return true
    }
}
