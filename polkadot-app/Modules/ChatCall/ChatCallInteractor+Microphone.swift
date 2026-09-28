import Foundation

extension ChatCallInteractor {
    func setMuted(_ isMuted: Bool, notifiesCallKit: Bool) async {
        if notifiesCallKit {
            callKitManager.requestMutedFromApp(isMuted)
        }

        let result = await callEngine.setMuted(isMuted)
        callKitManager.confirmMutedState(isSuccessful: isMuted == result)

        await presenter?.didUpdateMuteState(result)
    }

    /// The call connects even without the microphone; muting before `connect()` creates the audio track disabled.
    func startMutedIfNeeded(for microphoneAccess: CallMicrophoneAccess) async {
        guard microphoneAccess != .granted else {
            return
        }

        logger.warning("Microphone not available (\(microphoneAccess)), answering muted")
        await setMuted(true, notifiesCallKit: true)

        if microphoneAccess == .denied {
            await presenter?.didRequireMicrophoneAccess()
        }
    }

    func unmute(notifiesCallKit: Bool) async {
        guard !permissionsService.isMicrophoneGranted else {
            await setMuted(false, notifiesCallKit: notifiesCallKit)
            return
        }

        if !notifiesCallKit {
            // A CallKit action must not wait on a prompt that may only appear after unlock.
            callKitManager.confirmMutedState(isSuccessful: false)
        }

        await presenter?.didUpdateMuteState(true)

        let microphoneAccess = await permissionsService.resolveMicrophoneAccess(prompting: .always)

        guard !isEnding else {
            return
        }

        switch microphoneAccess {
        case .granted:
            await setMuted(false, notifiesCallKit: true)
        case .denied:
            await presenter?.didRequireMicrophoneAccess()
        case .refused,
             .deferred:
            logger.warning("Microphone access not granted, staying muted")
        }
    }
}
