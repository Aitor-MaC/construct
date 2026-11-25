import AppKit
import MacterminalCore
import SwiftUI

/// Muestra en vivo la lluvia, el CRT y una línea de prompt con la intensidad y la fuente elegidas,
/// usando las mismas vistas que el panel.
struct IntensityPreviewView: NSViewRepresentable {
  let intensity: Intensity
  let fontFamily: String
  let fontSize: Double

  func makeNSView(context: Context) -> IntensityPreviewStage {
    IntensityPreviewStage(intensity: intensity, font: font)
  }

  func updateNSView(_ stage: IntensityPreviewStage, context: Context) {
    stage.update(intensity: intensity, font: font)
  }

  static func dismantleNSView(_ stage: IntensityPreviewStage, coordinator: ()) {
    stage.stop()
  }

  /// Misma resolución que el terminal: si el nombre no existe, la monoespaciada del sistema.
  private var font: NSFont {
    NSFont(name: fontFamily, size: fontSize)
      ?? NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
  }
}

final class IntensityPreviewStage: NSView {
  private static let promptRow = 1
  private let rain: RainCanvasView
  private let crt: CRTOverlayView
  private let prompt = NSTextField(labelWithString: "~/projects/zion ❯ ls -la")
  private var font: NSFont

  init(intensity: Intensity, font: NSFont) {
    self.font = font
    let cell = Self.cellSize(for: font)
    rain = RainCanvasView(intensity: intensity, cellSize: cell, rows: 1, columns: 1)
    crt = CRTOverlayView(intensity: intensity)
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = MatrixTheme.nsColor(MatrixPalette.bg).cgColor
    setAccessibilityElement(false)
    prompt.textColor = MatrixTheme.nsColor(MatrixPalette.fg)
    prompt.font = font
    prompt.setAccessibilityElement(false)
    for view in [rain, prompt, crt] as [NSView] { addSubview(view) }
    rain.textRows = IndexSet(integer: Self.promptRow)
    rain.runState = rain.reduceMotion ? .frozen : .running(fps: 30)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isFlipped: Bool { true }

  func update(intensity: Intensity, font: NSFont) {
    rain.intensity = intensity
    crt.intensity = intensity
    guard font != self.font else { return }
    self.font = font
    prompt.font = font
    rain.cellSize = Self.cellSize(for: font)
    needsLayout = true
  }

  func stop() { rain.runState = .hidden }

  override func layout() {
    super.layout()
    let cell = rain.cellSize
    rain.frame = bounds
    crt.frame = bounds
    rain.columns = max(1, Int(bounds.width / cell.width))
    rain.rows = max(1, Int(bounds.height / cell.height))
    prompt.sizeToFit()
    prompt.frame.origin = CGPoint(x: cell.width, y: CGFloat(Self.promptRow) * cell.height)
  }

  /// Celda del panel: avance máximo de la fuente × interlineado 1,4 (dirección 4.2).
  private static func cellSize(for font: NSFont) -> CGSize {
    CGSize(
      width: max(1, font.maximumAdvancement.width), height: max(1, (font.pointSize * 1.4).rounded()))
  }
}
