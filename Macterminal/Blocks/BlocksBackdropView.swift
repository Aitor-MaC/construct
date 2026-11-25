import MacterminalCore
import SwiftUI

/// Rellenos de los bloques (error, hover, seleccionado). Va **debajo** de la terminal, cuyo
/// fondo es transparente: así el tinte queda detrás del texto y no lo apaga. Sin sombras ni
/// interacción; la capa de controles es `BlocksOverlayView`.
struct BlocksBackdropView: View {
  let tracker: BlockTracker
  let state: BlockOverlayState
  let viewport: ViewportSnapshot
  let resolve: (RowAnchor) -> Int?

  var body: some View {
    let geometry = BlockGeometry(viewport: viewport)
    ZStack(alignment: .topLeading) {
      ForEach(geometry.frames(of: tracker, resolve: resolve)) { frame in
        BlockFill(isFailure: isFailure(frame.id), rows: frame.rows, id: frame.id, state: state)
          .frame(maxWidth: .infinity)
          .frame(height: geometry.height(of: frame.rows))
          .padding(.top, geometry.top(of: frame.rows.lowerBound))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private func isFailure(_ id: UUID) -> Bool {
    tracker.blocks.last { $0.id == id }?.hasFailed ?? false
  }
}

extension CommandBlock {
  /// Terminó con un código distinto de 0; con código desconocido no se tiñe de error.
  var hasFailed: Bool { state == .finished && exitCode.map { $0 != 0 } ?? false }
}

/// Lee `hoveredRow` y `selectedID` aquí y no en el padre: mover el ratón solo redibuja los
/// rellenos, no recalcula la disposición. También hace de fondo del chip de la cabecera.
struct BlockFill: View {
  let isFailure: Bool
  let rows: Range<Int>
  let id: UUID
  let state: BlockOverlayState

  var body: some View {
    let isSelected = state.selectedID == id
    let isHovered = state.hoveredRow.map(rows.contains) ?? false
    ZStack {
      if isSelected {
        BlockTokens.surface1
      } else if isHovered {
        BlockTokens.surface1Hover
      }
      if isFailure { BlockTokens.errorTint }
    }
    .animation(BlockTokens.hover, value: isHovered)
  }
}
