import Testing

@testable import MacterminalCore

@MainActor @Suite struct ToastCenterTests {
  @Test func repeatingTheSameTextIsANewToast() throws {
    let center = ToastCenter()
    center.show("Salida copiada")
    let first = try #require(center.current)
    center.show("Salida copiada")
    let second = try #require(center.current)
    #expect(second.text == "Salida copiada")
    #expect(second != first)
  }

  @Test func dismissingAReplacedToastKeepsTheNewOne() throws {
    let center = ToastCenter()
    center.show("Salida copiada")
    let replaced = try #require(center.current)
    center.show("Salida copiada")
    center.dismiss(replaced)
    #expect(center.current?.text == "Salida copiada")
    #expect(center.current != replaced)
  }

  @Test func dismissingTheCurrentToastClearsIt() throws {
    let center = ToastCenter()
    center.show("Enlace no permitido")
    center.dismiss(try #require(center.current))
    #expect(center.current == nil)
  }
}
