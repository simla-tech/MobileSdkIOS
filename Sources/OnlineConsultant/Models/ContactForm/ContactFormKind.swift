/// Local SDK contact form scenario.
package enum ContactFormKind: String, Codable, Equatable, Sendable {

    /// Regular contact form submitted to `/contact/form`.
    case contact

    /// Offline contact form submitted to `/offline/form`.
    case offline
}
