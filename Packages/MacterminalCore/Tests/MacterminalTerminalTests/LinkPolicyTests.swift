import Foundation
import Testing

@testable import MacterminalTerminal

@Suite struct LinkPolicyTests {
  @Test(arguments: [
    ("https://example.com/a?b=c", LinkDecision.open),
    ("http://localhost:8080", .open),
    ("HTTPS://EXAMPLE.COM", .open),
    ("mailto:neo@zion.org", .open),
    ("file:///Users/neo/notas.txt", .revealInFinder),
    ("file:///x.command", .revealInFinder),
    ("file://localhost/tmp/a", .revealInFinder),
    ("file://evil.example/share/x.command", .reject),
    ("smb://server/share", .reject),
    ("vscode://file/etc/passwd", .reject),
    ("javascript:alert(1)", .reject),
    ("ftp://example.com/file", .reject),
    ("x-apple.systempreferences:com.apple.preference.security", .reject),
    ("https:///sin-host", .reject),
  ])
  func decidesByScheme(link: String, expected: LinkDecision) throws {
    let url = try #require(URL(string: link))
    #expect(LinkPolicy.decide(url) == expected)
  }

  /// `ls --hyperlink`, eza, fd y rg escriben `file://$(hostname)/ruta`.
  @Test(arguments: [
    ("file://neo-mac/Users/neo/a.txt", LinkDecision.revealInFinder),
    ("file://NEO-MAC.local/Users/neo/a.txt", .revealInFinder),
    ("file://neo-mac.local/tmp", .revealInFinder),
    ("file://otro-mac/Users/neo/a.txt", .reject),
    ("file://neo-mac.evil.example/x", .reject),
  ])
  func fileLinksWithTheLocalHostNameAreLocal(link: String, expected: LinkDecision) throws {
    let url = try #require(URL(string: link))
    #expect(LinkPolicy.decide(url, localHostName: "Neo-Mac.local") == expected)
  }

  @Test func currentHostNameIsLocal() throws {
    let url = try #require(URL(string: "file://\(LinkPolicy.currentHostName)/tmp"))
    #expect(LinkPolicy.decide(url) == .revealInFinder)
  }
}
