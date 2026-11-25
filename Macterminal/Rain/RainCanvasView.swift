import AppKit
import MacterminalCore
import OSLog

/// Lluvia digital detrás del texto del panel. Una sola capa: los glifos salen de un atlas
/// pre-rasterizado y un display link de la vista marca el ritmo solo mientras `runState` es
/// `.running`. El fondo es transparente (el `bg` lo pone el panel) y la vista no recibe clics.
/// Filas y columnas son las de la vista (0-based, fila 0 arriba), alineadas a la celda.
final class RainCanvasView: NSView {
  /// Fotograma fijo de Reduce Motion al 60 % (dirección 4.6).
  static let reducedMotionAlpha = 0.6

  var intensity: Intensity {
    didSet {
      guard intensity != oldValue else { return }
      engine = Self.makeEngine(columns, rows, intensity, &seeds)
      cursorLayer.intensity = intensity
      rebuildAtlas()
      refreshStill()
    }
  }
  var cellSize: CGSize {
    didSet {
      guard cellSize != oldValue else { return }
      cursorLayer.cellSize = cellSize
      rebuildAtlas()
      needsDisplay = true
    }
  }
  var rows: Int {
    didSet { if rows != oldValue { resizeEngine() } }
  }
  var columns: Int {
    didSet { if columns != oldValue { resizeEngine() } }
  }
  /// Filas de la vista con texto: el motor recorta ahí el alfa al tope de 0,10.
  var textRows = IndexSet() {
    didSet { if textRows != oldValue { refreshStill() } }
  }
  var typing = TypingState(idleSince: nil)
  /// Empieza oculta hasta que el panel calcule el estado con `RainPausePolicy`.
  var runState: RainRunState = .hidden {
    didSet {
      guard runState != oldValue else { return }
      logger.debug("rain state \(String(describing: self.runState), privacy: .public)")
      applyRunState()
    }
  }
  var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
    didSet {
      cursorLayer.reduceMotion = reduceMotion
      needsDisplay = true
    }
  }
  var increaseContrast = NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
    didSet { cursorLayer.increaseContrast = increaseContrast }
  }
  /// Glow y persistencia del cursor, en esta misma capa (encima de la lluvia, debajo del texto).
  let cursorLayer = PhosphorCursorLayer()

  private let logger = Logger(subsystem: "com.aitorgarcia.Macterminal", category: "rain")
  private var seeds: SplitMix64
  private var engine: RainEngine
  private var cells: [RainCell] = []
  private var atlas: RainGlyphAtlas?
  private var displayLink: CADisplayLink?
  private var lastTimestamp: CFTimeInterval?

  init(
    intensity: Intensity, cellSize: CGSize, rows: Int, columns: Int,
    seed: UInt64 = .random(in: .min ... .max)
  ) {
    self.intensity = intensity
    self.cellSize = cellSize
    self.rows = rows
    self.columns = columns
    seeds = SplitMix64(seed: seed)
    engine = Self.makeEngine(columns, rows, intensity, &seeds)
    super.init(frame: .zero)
    wantsLayer = true
    layerContentsRedrawPolicy = .onSetNeedsDisplay
    setAccessibilityElement(false)
    cursorLayer.intensity = intensity
    cursorLayer.cellSize = cellSize
    cursorLayer.reduceMotion = reduceMotion
    cursorLayer.increaseContrast = increaseContrast
    layer?.addSublayer(cursorLayer.layer)
    applyRunState()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) { nil }

  override var isOpaque: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func setFrameSize(_ newSize: NSSize) {
    super.setFrameSize(newSize)
    cursorLayer.frame = bounds
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    rebuildAtlas()
    applyRunState()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    rebuildAtlas()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    guard !cells.isEmpty, let atlas, let context = NSGraphicsContext.current?.cgContext
    else { return }
    let factor = runState == .frozen && reduceMotion ? Self.reducedMotionAlpha : 1
    let width = cellSize.width
    let height = cellSize.height
    let top = bounds.height
    context.interpolationQuality = .low
    for cell in cells {
      guard let image = atlas.image(for: cell.glyph, kind: cell.kind) else { continue }
      context.setAlpha(cell.alpha * factor)
      context.draw(
        image,
        in: CGRect(
          x: CGFloat(cell.column) * width, y: top - CGFloat(cell.row + 1) * height,
          width: width, height: height))
    }
  }

  // MARK: - Estado

  private var hasGeometry: Bool {
    rows > 0 && columns > 0 && cellSize.width.isFinite && cellSize.height.isFinite
      && cellSize.width > 0 && cellSize.height > 0
  }

  private static func makeEngine(
    _ columns: Int, _ rows: Int, _ intensity: Intensity, _ seeds: inout SplitMix64
  ) -> RainEngine {
    RainEngine(columns: columns, rows: rows, profile: intensity.profile, seed: seeds.next())
  }

  private func applyRunState() {
    switch runState {
    case .running(let fps):
      advance(by: .zero)
      startDisplayLink(fps: fps)
    case .frozen:
      stopDisplayLink()
      advance(by: .zero)
    case .hidden:
      stopDisplayLink()
      cells = []
    }
    needsDisplay = true
  }

  /// Recalcula el fotograma sin avanzar el tiempo, para que un cambio de geometría o de filas
  /// con texto se vea (y respete el tope) también con la lluvia congelada.
  private func refreshStill() {
    guard runState != .hidden else { return }
    advance(by: .zero)
    needsDisplay = true
  }

  private func resizeEngine() {
    engine.resize(columns: columns, rows: rows)
    refreshStill()
  }

  private func advance(by dt: Duration) {
    guard hasGeometry else {
      cells = []
      return
    }
    cells = engine.step(dt: dt, typing: typing, textRows: textRows).cells
  }

  private func rebuildAtlas() {
    atlas = RainGlyphAtlas(
      cellSize: cellSize, scale: window?.backingScaleFactor ?? 2,
      fontSize: RainGlyphAtlas.fontSize(for: intensity))
  }

  // MARK: - Display link

  private func startDisplayLink(fps: Int) {
    guard window != nil, fps > 0 else {
      stopDisplayLink()
      return
    }
    let link = displayLink ?? makeDisplayLink()
    let rate = Float(fps)
    link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
  }

  private func makeDisplayLink() -> CADisplayLink {
    let link = displayLink(target: self, selector: #selector(tick(_:)))
    link.add(to: .main, forMode: .common)
    displayLink = link
    lastTimestamp = nil
    return link
  }

  private func stopDisplayLink() {
    displayLink?.invalidate()
    displayLink = nil
    lastTimestamp = nil
  }

  @objc private func tick(_ link: CADisplayLink) {
    let elapsed = lastTimestamp.map { link.timestamp - $0 } ?? link.duration
    lastTimestamp = link.timestamp
    advance(by: .seconds(elapsed.isFinite ? max(0, elapsed) : 0))
    needsDisplay = true
  }
}
