/// Texto pegado por el usuario (⌘V). Lo demás del pegado (saltos de línea, bracketed paste) lo
/// gestiona SwiftTerm; aquí solo se quita lo que permitiría salir del modo bracketed (I3).
public enum PasteSanitizer {
  private static let bracketedPasteEnd = "\u{1b}[201~"

  /// En bucle: quitar una aparición puede juntar otra (`ESC [20` + `ESC [201~` + `1~`).
  public static func clean(_ text: String) -> String {
    var cleaned = text
    while cleaned.contains(bracketedPasteEnd) {
      cleaned = cleaned.replacing(bracketedPasteEnd, with: "")
    }
    return cleaned
  }
}
