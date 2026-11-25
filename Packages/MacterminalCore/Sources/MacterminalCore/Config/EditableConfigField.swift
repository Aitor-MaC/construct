/// Campo de texto de Ajustes ligado a una clave del config. Solo escribe lo que el usuario
/// tecleó: sin edición pendiente refleja siempre el valor del archivo, tenga o no el foco, así
/// que perder el foco nunca reescribe un valor antiguo encima de un cambio externo.
public struct EditableConfigField {
  public enum Write: Equatable, Sendable {
    case set(String)
    case remove
  }

  public private(set) var draft: String
  private var isEdited = false
  /// Sanea el borrador antes de escribirlo; `nil` significa "borrar la clave".
  private let normalize: (String) -> String?

  public init(value: String?, normalize: @escaping (String) -> String?) {
    draft = value ?? ""
    self.normalize = normalize
  }

  /// Texto tecleado por el usuario; el mismo texto que ya había no cuenta como edición.
  public mutating func edit(_ text: String) {
    guard text != draft else { return }
    draft = text
    isEdited = true
  }

  /// Valor nuevo del config. Con una edición pendiente gana lo que se está escribiendo; si el
  /// borrador ya equivale al valor (p. ej. "Thomas " tras guardar "Thomas" en una pausa), se
  /// deja tal cual para no comerse el espacio que se está tecleando.
  public mutating func sync(external value: String?) {
    guard !isEdited, normalize(draft) != value else { return }
    draft = value ?? ""
  }

  /// Escritura que toca hacer al confirmar (⏎, pausa al teclear o pérdida del foco), o `nil`
  /// si no hubo edición o el resultado ya es lo guardado. Consume la edición.
  public mutating func commit(saved: String?) -> Write? {
    guard isEdited else { return nil }
    isEdited = false
    let value = normalize(draft)
    guard value != saved else { return nil }
    return value.map(Write.set) ?? .remove
  }
}
