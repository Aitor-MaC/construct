import Testing

@testable import MacterminalCore

@Suite("EditableConfigField")
struct EditableConfigFieldTests {
  private func greetingField(_ value: String?) -> EditableConfigField {
    EditableConfigField(value: value, normalize: GreetingName.sanitize)
  }

  @Test func externalChangeWithoutEditingIsReflectedAndNotWritten() {
    var field = greetingField("Neo")
    field.sync(external: "Trinity")
    #expect(field.draft == "Trinity")
    #expect(field.commit(saved: "Trinity") == nil)
  }

  @Test func blurWithoutEditingNeverWritesTheOldValue() {
    var field = greetingField("Neo")
    // El archivo cambia mientras el campo tiene el foco; al perderlo no se reescribe "Neo".
    field.sync(external: "Morpheus")
    #expect(field.commit(saved: "Morpheus") == nil)
    #expect(field.draft == "Morpheus")
  }

  @Test func editThenBlurWritesOnce() {
    var field = greetingField("Neo")
    field.edit("  Trinity ")
    #expect(field.commit(saved: "Neo") == .set("Trinity"))
    #expect(field.commit(saved: "Neo") == nil)
  }

  @Test func editingToTheSavedValueWritesNothing() {
    var field = greetingField("Neo")
    field.edit("Neo ")
    #expect(field.commit(saved: "Neo") == nil)
  }

  @Test func clearingRemovesTheKey() {
    var field = greetingField("Neo")
    field.edit("   ")
    #expect(field.commit(saved: "Neo") == .remove)
  }

  @Test func pendingEditSurvivesAnExternalChange() {
    var field = greetingField("Neo")
    field.edit("Tri")
    field.sync(external: "Morpheus")
    #expect(field.draft == "Tri")
  }

  @Test func settingTheSameTextIsNotAnEdit() {
    var field = greetingField("Neo")
    field.edit("Neo")
    field.sync(external: "Morpheus")
    #expect(field.draft == "Morpheus")
    #expect(field.commit(saved: "Morpheus") == nil)
  }

  @Test func savingDuringAPauseKeepsTheTrailingSpaceBeingTyped() {
    var field = greetingField(nil)
    field.edit("Thomas ")
    // La pausa de 600 ms guarda "Thomas"; la recarga del config no debe comerse el espacio.
    #expect(field.commit(saved: nil) == .set("Thomas"))
    field.sync(external: "Thomas")
    #expect(field.draft == "Thomas ")
    field.edit("Thomas Anderson")
    #expect(field.commit(saved: "Thomas") == .set("Thomas Anderson"))
  }

  @Test func savedValueArrivingBackStillAllowsLaterExternalChanges() {
    var field = greetingField("Neo")
    field.edit(" Trinity")
    #expect(field.commit(saved: "Neo") == .set("Trinity"))
    field.sync(external: "Trinity")
    field.sync(external: "Morpheus")
    #expect(field.draft == "Morpheus")
  }
}
