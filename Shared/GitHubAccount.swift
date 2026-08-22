import Foundation

struct GitHubAccount: Codable, Hashable, Identifiable, Sendable {
    var name: String
    var email: String

    var id: String { name }
    var gitName: String { name }
    var gitEmail: String { email }

    init(name: String, email: String) {
        self.name = name
        self.email = email
    }

    static func noreplyEmail(userID: String, login: String) -> String {
        "\(userID)+\(login)@users.noreply.github.com"
    }
}
