import Testing

@testable import MacterminalCore

@Suite struct ControlPicturesTests {
  @Test func plainCommandsAreUnchanged() {
    #expect(ControlPictures.visible("git log --oneline | head -n 5") == "git log --oneline | head -n 5")
    #expect(ControlPictures.visible("echo café 👩‍💻") == "echo café 👩‍💻")
  }

  @Test func c0ControlsBecomeTheirPictures() {
    #expect(ControlPictures.visible("ls\nrm -rf ~\r") == "ls␊rm -rf ~␍")
    #expect(ControlPictures.visible("a\u{1b}[2Jb\u{07}") == "a␛[2Jb␇")
    #expect(ControlPictures.visible("\u{00}\t\u{7f}") == "␀␉␡")
  }

  @Test func c1ControlsAreReplacedVisibly() {
    #expect(ControlPictures.visible("a\u{9b}31m") == "a\u{FFFD}31m")
  }
}
