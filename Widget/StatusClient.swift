import Foundation

struct StatusClient {
    func fetch() async -> SwitcherStatus {
        await SwitcherLoopbackClient().fetchStatus()
    }
}
