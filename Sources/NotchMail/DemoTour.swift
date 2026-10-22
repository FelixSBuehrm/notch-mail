import Foundation
import NotchCore

/// A scripted walk through the notch with demo mail, for the README animation:
/// `--demo-only --pin --capturable --tour`. Touches no account and no Keychain.
@MainActor
enum DemoTour {
    static func run(_ controller: NotchController) async {
        let mail = DemoMailSource.tourMessages()
        // 0 HTML report, 1 login code, 2 Sam's thread, 3… the rest.
        controller.send(.mailLoaded([mail[0], mail[2], mail[3], mail[4], mail[5]]))
        await pause(1.2)
        controller.send(.mailArrived(mail[1]))
        await pause(2.8)
        controller.send(.alertTimedOut)
        await pause(0.9)
        controller.send(.hoverChanged(true))
        await pause(2.4)
        controller.send(.selected(mail[0].id))
        await pause(3.0)
        controller.send(.backToList)
        await pause(1.0)
        controller.send(.selected(mail[2].id))
        await pause(1.8)
        controller.startReply(mail[2])
        await pause(0.8)
        for character in "Thursday 2pm works, I'll add my notes to the doc" {
            controller.composer?.instruction.append(character)
            await pause(0.035)
        }
        await pause(0.5)
        controller.composer?.writeDraft()
        await pause(3.2)
        controller.composer?.send()
        await pause(7.6)  // countdown, sending, then "Sent" beside the list
        controller.send(.hoverChanged(false))
    }

    private static func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }
}
