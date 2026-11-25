import CoreGraphics
import Foundation
import Observation

/// Estado de interacción de los bloques de un panel. Lo comparten el fondo (bajo el texto), la
/// capa de controles (sobre el texto) y las acciones ⌘↑/⌘↓; T14 crea uno por panel.
@MainActor @Observable final class BlockOverlayState {
  enum Region: Hashable {
    case control(String)
    case block(UUID)
  }

  private(set) var selectedID: UUID?
  /// Fila absoluta bajo el puntero; la escribe `BlocksOverlayHostingView` con su área de rastreo.
  var hoveredRow: Int?

  /// Zonas de la capa superior que aceptan clics, en su espacio de coordenadas. Fuera de los
  /// controles el clic va a la terminal; los bloques solo aceptan el clic secundario (menú).
  /// No se observan: cambian con cada desplazamiento y nadie dibuja a partir de ellas.
  @ObservationIgnored private(set) var controlRegions: [String: CGRect] = [:]
  @ObservationIgnored private(set) var blockRegions: [UUID: CGRect] = [:]

  func select(_ id: UUID) {
    selectedID = id
  }

  /// La selección de ⌘↑/⌘↓ dura hasta que se vuelve a escribir en la terminal (Escape incluido).
  /// Los atajos con ⌘ no la quitan: con ellos se navega y se copia el bloque seleccionado.
  func noteKeyDown(withCommand: Bool) {
    guard !withCommand, selectedID != nil else { return }
    selectedID = nil
  }

  func setRegion(_ rect: CGRect?, for region: Region) {
    switch region {
    case .control(let key): controlRegions[key] = rect
    case .block(let id): blockRegions[id] = rect
    }
  }

  func acceptsClick(at point: CGPoint, secondary: Bool) -> Bool {
    if controlRegions.values.contains(where: { $0.contains(point) }) { return true }
    return secondary && blockRegions.values.contains { $0.contains(point) }
  }
}
