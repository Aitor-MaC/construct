import MacterminalCore
import SwiftUI

/// Confirmación breve en la esquina inferior derecha, alimentada por `ToastCenter`. Un mensaje
/// nuevo sustituye al actual sin apilarse. No recibe foco ni ratón: se coloca encima del lienzo
/// y deja pasar los clics.
struct ToastView: View {
  /// Tiempo en pantalla de cada mensaje, sin contar la entrada.
  static let holdDuration = Duration.milliseconds(1800)

  let center: ToastCenter
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack(alignment: .bottomTrailing) {
      Color.clear
      if let toast = center.current {
        bubble(toast.text)
          .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 6)))
      }
    }
    .padding(16)
    .animation(OverlayStyle.enterExit, value: center.current == nil)
    .allowsHitTesting(false)
    .task(id: center.current?.id) { await hold() }
  }

  private func bubble(_ message: String) -> some View {
    Text(verbatim: message)
      .font(.system(size: 12))
      .foregroundStyle(MatrixTheme.color(MatrixPalette.fgBright))
      .lineLimit(1)
      .padding(.vertical, 8)
      .padding(.horizontal, 12)
      .background(OverlayStyle.surface, in: .rect(cornerRadius: 8))
      .overlay { RoundedRectangle(cornerRadius: 8).strokeBorder(OverlayStyle.border, lineWidth: 0.5) }
      .shadow(color: .black.opacity(0.45), radius: 12, y: 8)
  }

  /// Anuncia el aviso y lo retira pasado `holdDuration`, salvo que otro lo haya sustituido: la
  /// tarea va ligada al `id` del aviso, así que cada `show` (aunque repita el texto) la cancela y
  /// la del nuevo empieza de cero.
  private func hold() async {
    guard let toast = center.current else { return }
    AccessibilityNotification.Announcement(toast.text).post()
    do {
      try await Task.sleep(for: Self.holdDuration)
    } catch {
      return
    }
    center.dismiss(toast)
  }
}
