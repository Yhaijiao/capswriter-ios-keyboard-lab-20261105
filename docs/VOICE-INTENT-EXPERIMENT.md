# Isolated public voice intent experiment

This branch is a prototype, not v0.4.5 and not a proven fix. No phone, account, or server was modified by this task. No private API, host bundle selector, responder-chain open, UIApplication from extension, App Groups, push notification, or paid capability is used.

## Evidence and uncertainty

- Apple AudioRecordingIntent (iOS18+) requires a Live Activity before recording and throughout recording. Without it recording stops: https://developer.apple.com/documentation/appintents/audiorecordingintent
- Apple LiveActivityIntent (iOS17+) explicitly says the system launches the containing app process without opening the app, performs the intent, and starts its Live Activity: https://developer.apple.com/documentation/appintents/liveactivityintent
- The prototype combines these protocols, hosts a SwiftUI Button(intent:) in the keyboard, and places microphone ownership exclusively in the containing app. Whether keyboard dispatch actually reaches the app after force-quit MUST be established on device. Extensions contain only a fail-closed intent body and never access the microphone.
- On iOS26+, the intent explicitly requests supportedModes.background; on18-25 it uses openAppWhenRun=false. Apple runtime modes are suggestions that special protocol/runtime conditions may override, so device behavior remains authoritative: https://developer.apple.com/documentation/appintents/appintent/supportedmodes
- Apple AppIntent.allowedExecutionTargets can explicitly choose .main, but official availability metadata is iOS27+. It is deliberately NOT used for iOS26.6.1: https://developer.apple.com/documentation/appintents/appintent/allowedexecutiontargets
- KeyboardKit's maintainer reports SwiftUI Link can open the containing app with Full Access on iOS26 (issue966). This supports an alternate app-jump experiment, not an automatic-return claim: https://github.com/KeyboardKit/KeyboardKit/issues/966
- User tested Typeless after force-quit: it briefly opens its app, then returns automatically to the prior input app. This product observation is accepted. We have not established its implementation and must not assert iOS universally forbids that experience.
- No guaranteed public generic return-to-arbitrary-host API was identified. sourceApplication supplies an identifier, not a public launch URL. No private host lookup or navigation action is added. requestSceneSessionDestruction is not assumed to return to the original app on iPhone. The intent experiment may instead avoid a visible jump if system dispatch works as documented.

## Files and behavior

- ios/IntentShared/KeyboardRecordingIntent.swift: Start and Stop intents, dual AudioRecordingIntent/LiveActivityIntent, iOS18 availability, no credential parameters, extension bodies fail closed.
- ios/IntentShared/RecordingActivityAttributes.swift: local ActivityKit attributes, no transcript or token.
- ios/App/VoiceIntentCoordinator.swift: singleton owns VoiceSession even when Lab controller is absent, validates pre-existing app pairing and granted microphone/Live Activity authorization, starts a local activity before arming, waits at most20seconds, cleans up on failure, and ends capture when activity is dismissed.
- ios/App/VoiceSession.swift: normal foreground guard remains. Background arm additionally requires a matching currently active own Live Activity ID supplied by the intent coordinator. Default/manual/auto-start calls pass no such ID.
- ios/App/AppDelegate.swift: Lab UI shares the singleton session; no second audio engine.
- ios/Keyboard/KeyboardVoiceIntentControl.swift and controller wiring: iOS18+ separate orange experimental button appears beside the connection-test button under Hotwords -> gear. Normal mic behavior is untouched. A simultaneous explicit tap initiates bounded readiness polling; once app agent is ready the existing recording start flow runs. No new server endpoint or mutable server state protocol is added.
- ios/VoiceActivity/RecordingActivityWidget.swift: local lock-screen/Dynamic Island UI, visible microphone-session status/countdown and Stop action. No push token.
- project.yml: embeds the extra WidgetKit extension, sets NSSupportsLiveActivities, shares intent declarations and defines CAPSWRITER_CONTAINING_APP only for the app target. Free Personal Team signing and this extra extension still need actual signing verification. Keep BOTH extension plug-ins when sideloading this experiment.

## Required validation

1. XcodeGen + physical iPhone build and simulator build. Tree-sitter is only syntax validation, not compilation.
2. Inspect App Intents metadata extraction for each target. Confirm Start intent dispatches to app, not the keyboard stub. Do not remove the stub's fail-closed behavior to make a demo appear successful.
3. Install the clearly labeled experimental build after compilation/package checks, preserving the stable package for rollback. Pair app and keyboard to the same endpoint; grant mic in the foreground and allow local Live Activities.
4. Test A: Lab remains backgrounded. In Notes, Hotwords -> gear -> experimental start. Verify activity appears, original input app stays or automatically resumes, microphone indicator is active, recording starts without a second tap and final result inserts once.
5. Test B: force-quit Lab first, then repeat from Notes. Record whether app opens, whether it returns automatically, whether microphone actually captures speech and whether agent-ready becomes true. Never claim cold-start success from a Live Activity banner alone.
6. Test C: another host input app, no Full Access, revoked mic, disabled Live Activities, invalid/expired pairing, network unavailable and activity dismissal. Failures must stop capture and remove activity. Default iOS17 foreground behavior must remain.
7. Validate stop, interruption and10minute expiry, repeated attempts after force-quit, and no duplicate microphone engines or stale activity accumulation.

## Validation performed here

Created only in the isolated voice-intent worktree. All20Swift files parse with tree-sitter after editing. No Xcode compiler is installed on this Windows host. NO Xcode, signing, installation, keyboard dispatch or force-quit recovery result is claimed. Root should review/commit this branch and run a dedicated CI build without replacing stable v0.4.5 artifacts.
