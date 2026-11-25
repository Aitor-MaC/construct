import Foundation

public struct TypingState: Sendable, Equatable {
  /// Tiempo sin teclear; `nil` = sin dato (se trata como "no está tecleando").
  public var idleSince: Duration?
  public init(idleSince: Duration?) { self.idleSince = idleSince }
}

public struct RainCell: Sendable, Equatable {
  public enum Kind: Sendable, Equatable { case head, trail }
  public let column: Int
  public let row: Int
  public let glyph: Character
  public let kind: Kind
  public let alpha: Double
}

public struct RainFrame: Sendable, Equatable {
  public var cells: [RainCell]
}

public struct RainEngine: Sendable {
  private struct Stream: Sendable {
    var column: Int
    var head: Double
    var speed: Double
    var length: Int
    /// glyphs[d] = glifo a distancia d de la cabeza (0...length).
    var glyphs: [Character]

    mutating func mutate(rate: Double, rng: inout SplitMix64) {
      guard rate > 0 else { return }
      let probability = min(1, rate)
      for index in glyphs.indices where Double.random(in: 0..<1, using: &rng) < probability {
        glyphs[index] = RainGlyphs.random(using: &rng)
      }
    }
  }

  private static let maxDimension = 4096
  private static let maxStep = 1.0

  public private(set) var columns: Int
  public private(set) var rows: Int
  private let profile: IntensityProfile
  private var rng: SplitMix64
  private var streams: [Stream] = []
  private var typingLevel = 1.0

  public init(columns: Int, rows: Int, profile: IntensityProfile, seed: UInt64) {
    self.columns = Self.clamp(columns)
    self.rows = Self.clamp(rows)
    self.profile = profile
    self.rng = SplitMix64(seed: seed)
    rebuildStreams()
  }

  public mutating func resize(columns: Int, rows: Int) {
    self.columns = Self.clamp(columns)
    self.rows = Self.clamp(rows)
    rebuildStreams()
  }

  public mutating func step(dt: Duration, typing: TypingState, textRows: IndexSet) -> RainFrame {
    let seconds = Self.seconds(dt)
    updateTypingLevel(seconds: seconds, typing: typing)
    for index in streams.indices { advance(index, seconds: seconds) }
    guard rows > 0, columns > 0 else { return RainFrame(cells: []) }
    var cells: [RainCell] = []
    for index in streams.indices {
      streams[index].mutate(rate: profile.mutationRate * seconds, rng: &rng)
      let stream = streams[index]
      let headRow = Int(stream.head.rounded(.down))
      for distance in 0...stream.length {
        let row = headRow - distance
        guard row >= 0, row < rows else { continue }
        let base =
          distance == 0
          ? profile.headAlpha
          : profile.trailAlpha * (1 - Double(distance - 1) / Double(stream.length))
        var alpha = base * typingLevel
        // Único sitio donde se recorta el alfa sobre filas con texto (A3).
        if textRows.contains(row) { alpha = min(alpha, profile.textRowAlphaCap) }
        guard alpha > 0 else { continue }
        cells.append(
          RainCell(
            column: stream.column, row: row, glyph: stream.glyphs[distance],
            kind: distance == 0 ? .head : .trail, alpha: min(1, alpha)))
      }
    }
    return RainFrame(cells: cells)
  }

  // MARK: - Internals

  private static func clamp(_ value: Int) -> Int { min(max(0, value), maxDimension) }

  private static func seconds(_ dt: Duration) -> Double {
    let (s, atto) = dt.components
    let value = Double(s) + Double(atto) / 1e18
    return value.isFinite ? min(max(0, value), maxStep) : 0
  }

  private mutating func rebuildStreams() {
    streams = []
    guard columns > 0 else { return }
    let count = min(columns, Int((profile.activeColumnFraction * Double(columns)).rounded()))
    var pool = Array(0..<columns)
    pool.shuffle(using: &rng)
    for column in pool.prefix(count) {
      var stream = makeStream(column: column)
      stream.head = Double.random(in: 0..<Double(max(rows, 1)), using: &rng)
      streams.append(stream)
    }
  }

  private mutating func makeStream(column: Int) -> Stream {
    let length = Int.random(in: profile.trailLength, using: &rng)
    let speed = Double.random(in: profile.speed, using: &rng)
    let glyphs = (0...length).map { _ in RainGlyphs.random(using: &rng) }
    return Stream(column: column, head: 0, speed: speed, length: length, glyphs: glyphs)
  }

  private mutating func advance(_ index: Int, seconds: Double) {
    var stream = streams[index]
    let before = Int(stream.head.rounded(.down))
    stream.head += stream.speed * seconds
    let moved = min(Int(stream.head.rounded(.down)) - before, stream.length + 1)
    if moved > 0 {
      let fresh = (0..<moved).map { _ in RainGlyphs.random(using: &rng) }
      stream.glyphs = Array((fresh + stream.glyphs).prefix(stream.length + 1))
    }
    if Int(stream.head.rounded(.down)) - stream.length >= rows {
      streams[index] = relocated(stream)
    } else {
      streams[index] = stream
    }
  }

  /// Reinicia el hilo en otra columna libre (o la misma si no hay), manteniendo la fracción activa.
  private mutating func relocated(_ old: Stream) -> Stream {
    let used = Set(streams.map(\.column))
    var column = old.column
    if columns > used.count {
      for _ in 0..<8 {
        let candidate = Int.random(in: 0..<columns, using: &rng)
        if !used.contains(candidate) {
          column = candidate
          break
        }
      }
    }
    return makeStream(column: column)
  }

  private mutating func updateTypingLevel(seconds: Double, typing: TypingState) {
    let low = profile.typingAlphaMultiplier
    let isTyping = typing.idleSince.map { $0 < profile.typingIdleDelay } ?? false
    let target = isTyping ? low : 1
    let span = 1 - low
    guard span > 0 else {
      typingLevel = 1
      return
    }
    if target < typingLevel {
      typingLevel = max(target, typingLevel - span * seconds / Self.seconds(profile.typingFadeOut))
    } else if target > typingLevel {
      typingLevel = min(target, typingLevel + span * seconds / Self.seconds(profile.typingFadeIn))
    }
  }
}
