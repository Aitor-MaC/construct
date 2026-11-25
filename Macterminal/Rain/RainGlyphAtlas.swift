import AppKit
import CoreText
import MacterminalCore

/// Glifos de la lluvia rasterizados una sola vez, en espejo horizontal, en un único bitmap.
/// Cada glifo es un recorte de ese bitmap: dibujar un fotograma no maqueta texto.
final class RainGlyphAtlas {
  /// Hiragino Sans W3 a 14 pt (16 pt en Inmersivo), según la dirección de diseño (4.2).
  static func fontSize(for intensity: Intensity) -> CGFloat { intensity == .inmersivo ? 16 : 14 }

  private static let fontName = "HiraginoSans-W3" as CFString

  private let headImages: [Character: CGImage]
  private let trailImages: [Character: CGImage]

  /// `nil` si la geometría no permite un bitmap (celda vacía o escala no válida).
  init?(cellSize: CGSize, scale: CGFloat, fontSize: CGFloat) {
    let pixelWidth = Self.pixels(cellSize.width * scale)
    let pixelHeight = Self.pixels(cellSize.height * scale)
    let glyphs = RainGlyphs.all
    guard let pixelWidth, let pixelHeight, fontSize.isFinite, fontSize > 0,
      let space = CGColorSpace(name: CGColorSpace.sRGB),
      let context = CGContext(
        data: nil, width: pixelWidth * glyphs.count, height: pixelHeight * 2,
        bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    let font = CTFontCreateWithName(Self.fontName, fontSize * scale, nil)
    let tints = [MatrixPalette.ph50, MatrixPalette.ph400].map { MatrixTheme.nsColor($0).cgColor }
    for (band, tint) in tints.enumerated() {
      for (index, glyph) in glyphs.enumerated() {
        let cell = CGRect(
          x: index * pixelWidth, y: band * pixelHeight, width: pixelWidth, height: pixelHeight)
        Self.drawMirrored(glyph, font: font, color: tint, in: cell, context: context)
      }
    }
    guard let atlas = context.makeImage() else { return nil }
    // El bitmap tiene el origen abajo; los recortes de CGImage, arriba.
    func slice(band: Int) -> [Character: CGImage] {
      var images: [Character: CGImage] = [:]
      for (index, glyph) in glyphs.enumerated() {
        let rect = CGRect(
          x: index * pixelWidth, y: (1 - band) * pixelHeight, width: pixelWidth,
          height: pixelHeight)
        images[glyph] = atlas.cropping(to: rect)
      }
      return images
    }
    headImages = slice(band: 0)
    trailImages = slice(band: 1)
  }

  func image(for glyph: Character, kind: RainCell.Kind) -> CGImage? {
    kind == .head ? headImages[glyph] : trailImages[glyph]
  }

  private static func pixels(_ length: CGFloat) -> Int? {
    guard length.isFinite, length >= 1, length <= 4096 else { return nil }
    return Int(length.rounded(.up))
  }

  private static func drawMirrored(
    _ glyph: Character, font: CTFont, color: CGColor, in cell: CGRect, context: CGContext
  ) {
    let text = NSAttributedString(
      string: String(glyph),
      attributes: [.init(kCTFontAttributeName as String): font, .foregroundColor: color])
    let line = CTLineCreateWithAttributedString(text)
    var ascent: CGFloat = 0
    var descent: CGFloat = 0
    let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
    context.saveGState()
    context.clip(to: cell)
    context.translateBy(x: cell.maxX, y: cell.minY)
    context.scaleBy(x: -1, y: 1)
    context.textPosition = CGPoint(
      x: (cell.width - width) / 2, y: (cell.height - ascent - descent) / 2 + descent)
    CTLineDraw(line, context)
    context.restoreGState()
  }
}
