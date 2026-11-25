import AppKit
import MacterminalCore

/// Escenario de las previews: el `RainEngine` real con la geometría de un panel de 13 pt y las
/// filas con texto y el cursor salidos de `ViewportSnapshot`, como se los pasará el panel.
private func rainPreviewStage(
  _ intensity: Intensity, runState: RainRunState = .running(fps: 30), reduceMotion: Bool = false,
  greeting: Bool = false
) -> NSView {
  let font =
    NSFont(name: "MonaspaceKryptonNF-Regular", size: 13)
    ?? NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
  let cell = CGSize(width: font.maximumAdvancement.width, height: (13 * 1.4).rounded())
  let columns = 88
  let rows = 24
  let snapshot = ViewportSnapshot(
    topRow: 120, rows: rows, columns: columns, cellSize: cell,
    occupiedRows: IndexSet(120...127), cursor: GridPosition(col: 9, row: 127))
  let size = NSSize(width: CGFloat(columns) * cell.width, height: CGFloat(rows) * cell.height)

  let stage = NSView(frame: NSRect(origin: .zero, size: size))
  stage.wantsLayer = true
  stage.layer?.backgroundColor = MatrixTheme.nsColor(MatrixPalette.bg).cgColor

  let rain = RainCanvasView(
    intensity: intensity, cellSize: cell, rows: rows, columns: columns, seed: 0x5EED)
  rain.reduceMotion = reduceMotion
  rain.textRows = snapshot.viewportOccupiedRows()
  rain.cursorLayer.cursor = snapshot.viewportCursor()
  rain.runState = runState
  let crt = CRTOverlayView(intensity: intensity)
  crt.reduceMotion = reduceMotion
  var layers: [NSView] = [rain, crt]
  if greeting {
    layers.append(WakeUpGreetingView(givenName: "Neo", reduceMotion: reduceMotion) {})
  }
  for view in layers {
    view.frame = stage.bounds
    view.autoresizingMask = [.width, .height]
    stage.addSubview(view)
  }
  return stage
}

#Preview("Subtle") { rainPreviewStage(.sutil) }
#Preview("Balanced") { rainPreviewStage(.equilibrado) }
#Preview("Immersive") { rainPreviewStage(.inmersivo) }
#Preview("Reduce Motion · Balanced") {
  rainPreviewStage(.equilibrado, runState: .frozen, reduceMotion: true)
}
#Preview("Wake up · Immersive") { rainPreviewStage(.inmersivo, greeting: true) }
#Preview("Wake up · Reduce Motion") {
  rainPreviewStage(.inmersivo, runState: .frozen, reduceMotion: true, greeting: true)
}
