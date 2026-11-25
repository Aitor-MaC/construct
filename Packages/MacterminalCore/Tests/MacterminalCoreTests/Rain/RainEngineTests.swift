import Foundation
import Testing

@testable import MacterminalCore

@Suite struct RainEngineTests {
  static let idle = TypingState(idleSince: nil)

  @Test func sameSeedSameFrames() {
    var a = RainEngine(columns: 40, rows: 20, profile: Intensity.equilibrado.profile, seed: 42)
    var b = RainEngine(columns: 40, rows: 20, profile: Intensity.equilibrado.profile, seed: 42)
    for _ in 0..<200 {
      let fa = a.step(dt: .milliseconds(33), typing: Self.idle, textRows: [])
      let fb = b.step(dt: .milliseconds(33), typing: Self.idle, textRows: [])
      #expect(fa == fb)
    }
  }

  @Test func differentSeedsDiffer() {
    var a = RainEngine(columns: 40, rows: 20, profile: Intensity.equilibrado.profile, seed: 1)
    var b = RainEngine(columns: 40, rows: 20, profile: Intensity.equilibrado.profile, seed: 2)
    #expect(
      a.step(dt: .milliseconds(33), typing: Self.idle, textRows: [])
        != b.step(dt: .milliseconds(33), typing: Self.idle, textRows: []))
  }

  @Test(arguments: Intensity.allCases)
  func textRowsNeverExceedCap(intensity: Intensity) {
    var engine = RainEngine(columns: 30, rows: 24, profile: intensity.profile, seed: 7)
    let text = IndexSet(integersIn: 5..<15)
    var sawNonTextCellAboveCap = false
    for _ in 0..<10_000 {
      let frame = engine.step(dt: .milliseconds(33), typing: Self.idle, textRows: text)
      for cell in frame.cells {
        if text.contains(cell.row) {
          #expect(cell.alpha <= 0.10)
        } else if cell.alpha > 0.10 {
          sawNonTextCellAboveCap = true
        }
      }
    }
    #expect(sawNonTextCellAboveCap || intensity == .sutil)
  }

  @Test func outOfRangeTextRowsAreIgnored() {
    var engine = RainEngine(columns: 10, rows: 10, profile: Intensity.inmersivo.profile, seed: 3)
    let frame = engine.step(
      dt: .milliseconds(33), typing: Self.idle, textRows: IndexSet([10, 99, 100_000]))
    #expect(frame.cells.contains { $0.alpha > 0.10 })
  }

  @Test func scrolledViewportKeepsCapAfterConversionAndResize() {
    var engine = RainEngine(columns: 80, rows: 40, profile: Intensity.inmersivo.profile, seed: 9)
    let occupied = IndexSet(integersIn: 2000..<2040)
    let snapshot = ViewportSnapshot(
      topRow: 2000, rows: 40, columns: 80, cellSize: CGSize(width: 8, height: 16),
      occupiedRows: occupied, cursor: nil)
    for _ in 0..<300 {
      let frame = engine.step(
        dt: .milliseconds(33), typing: Self.idle, textRows: snapshot.viewportOccupiedRows())
      #expect(frame.cells.allSatisfy { $0.alpha <= 0.10 })
    }
    engine.resize(columns: 80, rows: 30)
    let fresh = ViewportSnapshot(
      topRow: 2010, rows: 30, columns: 80, cellSize: CGSize(width: 8, height: 16),
      occupiedRows: IndexSet(integersIn: 2010..<2040), cursor: nil)
    for _ in 0..<300 {
      let frame = engine.step(
        dt: .milliseconds(33), typing: Self.idle, textRows: fresh.viewportOccupiedRows())
      #expect(frame.cells.allSatisfy { $0.alpha <= 0.10 && $0.row < 30 })
    }
  }

  @Test(arguments: Intensity.allCases)
  func activeColumnFractionMatchesProfile(intensity: Intensity) {
    var engine = RainEngine(columns: 100, rows: 50, profile: intensity.profile, seed: 11)
    var total = 0.0
    let frames = 200
    for _ in 0..<frames {
      let frame = engine.step(dt: .milliseconds(33), typing: Self.idle, textRows: [])
      total += Double(Set(frame.cells.map(\.column)).count) / 100
    }
    #expect(abs(total / Double(frames) - intensity.profile.activeColumnFraction) <= 0.05)
  }

  @Test(arguments: Intensity.allCases)
  func headSpeedFallsInRange(intensity: Intensity) {
    let profile = intensity.profile
    var engine = RainEngine(columns: 20, rows: 4000, profile: profile, seed: 5)
    func heads(_ frame: RainFrame) -> [Int: Int] {
      Dictionary(uniqueKeysWithValues: frame.cells.filter { $0.kind == .head }.map { ($0.column, $0.row) })
    }
    let start = heads(engine.step(dt: .zero, typing: Self.idle, textRows: []))
    let end = heads(engine.step(dt: .seconds(1), typing: Self.idle, textRows: []))
    #expect(!start.isEmpty)
    for (column, row) in start {
      guard let later = end[column] else {
        Issue.record("cabeza perdida en la columna \(column)")
        continue
      }
      let speed = Double(later - row)
      #expect(speed >= profile.speed.lowerBound - 1 && speed <= profile.speed.upperBound + 1)
    }
  }

  @Test func extremeInputsDoNotCrashOrLeakCells() {
    var engine = RainEngine(columns: 20, rows: 10, profile: Intensity.inmersivo.profile, seed: 1)
    for dt: Duration in [.zero, .seconds(1_000_000), .seconds(-5), .milliseconds(1)] {
      let frame = engine.step(dt: dt, typing: TypingState(idleSince: .seconds(-1)), textRows: [])
      #expect(frame.cells.allSatisfy { (0..<20).contains($0.column) && (0..<10).contains($0.row) })
    }
    for size in [(0, 0), (0, 10), (10, 0), (-3, -3), (1, 1), (500, 3)] {
      engine.resize(columns: size.0, rows: size.1)
      let frame = engine.step(dt: .milliseconds(33), typing: Self.idle, textRows: [])
      let cols = max(0, size.0)
      let rows = max(0, size.1)
      #expect(frame.cells.allSatisfy { $0.column < cols && $0.row < rows })
    }
    var empty = RainEngine(columns: 0, rows: 0, profile: Intensity.sutil.profile, seed: 1)
    #expect(empty.step(dt: .seconds(1), typing: Self.idle, textRows: []).cells.isEmpty)
  }

  @Test func hideModeFadesOnTypingAndReturnsAfterSixSeconds() {
    var engine = RainEngine(columns: 50, rows: 30, profile: Intensity.sutil.profile, seed: 4)
    var frame = RainFrame(cells: [])
    for _ in 0..<8 {  // 0,24 s tecleando: fundido de 0,2 s completado
      frame = engine.step(dt: .milliseconds(30), typing: TypingState(idleSince: .zero), textRows: [])
    }
    #expect(frame.cells.allSatisfy { $0.alpha == 0 })
    frame = engine.step(
      dt: .milliseconds(30), typing: TypingState(idleSince: .seconds(5.9)), textRows: [])
    #expect(frame.cells.isEmpty)
    var fullyBack = false
    for _ in 0..<25 {  // 0,75 s tras 6 s sin teclear: regreso en 0,6 s
      frame = engine.step(
        dt: .milliseconds(30), typing: TypingState(idleSince: .seconds(6.1)), textRows: [])
    }
    let maxAlpha = frame.cells.map(\.alpha).max() ?? 0
    fullyBack = maxAlpha == Intensity.sutil.profile.headAlpha
    #expect(fullyBack)
  }

  @Test func hideModeFadeOutTakesAboutTwoTenths() {
    var engine = RainEngine(columns: 50, rows: 30, profile: Intensity.sutil.profile, seed: 4)
    let half = engine.step(
      dt: .milliseconds(100), typing: TypingState(idleSince: .zero), textRows: [])
    let maxHalf = half.cells.map(\.alpha).max() ?? 0
    #expect(maxHalf > 0 && maxHalf < Intensity.sutil.profile.headAlpha)
  }

  @Test func dimModeHalvesAlpha() {
    let profile = Intensity.equilibrado.profile
    var engine = RainEngine(columns: 50, rows: 30, profile: profile, seed: 4)
    var frame = RainFrame(cells: [])
    for _ in 0..<30 {
      frame = engine.step(dt: .milliseconds(30), typing: TypingState(idleSince: .zero), textRows: [])
    }
    let maxAlpha = frame.cells.map(\.alpha).max() ?? 0
    #expect(abs(maxAlpha - profile.headAlpha * 0.5) < 1e-9)
  }

  /// Fraccion de glifos persistentes (misma celda, cabeza sin desplazarse) que cambian por paso.
  static func mutationFraction(intensity: Intensity, steps: Int) -> Double {
    var engine = RainEngine(columns: 60, rows: 4000, profile: intensity.profile, seed: 21)
    var previous = engine.step(dt: .zero, typing: idle, textRows: [])
    var compared = 0
    var changed = 0
    for _ in 0..<steps {
      let next = engine.step(dt: .milliseconds(10), typing: idle, textRows: [])
      let headBefore = Dictionary(
        uniqueKeysWithValues: previous.cells.filter { $0.kind == .head }.map { ($0.column, $0.row) })
      let stable = Set(
        next.cells.filter { $0.kind == .head && headBefore[$0.column] == $0.row }.map(\.column))
      var old: [Int: Character] = [:]
      for cell in previous.cells where stable.contains(cell.column) {
        old[cell.column * 10_000 + cell.row] = cell.glyph
      }
      for cell in next.cells where stable.contains(cell.column) {
        if let glyph = old[cell.column * 10_000 + cell.row] {
          compared += 1
          if glyph != cell.glyph { changed += 1 }
        }
      }
      previous = next
    }
    return compared == 0 ? 0 : Double(changed) / Double(compared)
  }

  @Test(arguments: [Intensity.sutil, .equilibrado, .inmersivo])
  func glyphMutationFollowsMutationRate(intensity: Intensity) {
    let expected = intensity.profile.mutationRate * 0.01 * Double(RainGlyphs.all.count - 1)
      / Double(RainGlyphs.all.count)
    let observed = Self.mutationFraction(intensity: intensity, steps: 300)
    #expect(abs(observed - expected) <= expected * 0.25)
  }

  @Test func higherMutationRateMutatesMore() {
    #expect(
      Self.mutationFraction(intensity: .sutil, steps: 200)
        < Self.mutationFraction(intensity: .inmersivo, steps: 200))
  }

  @Test func glyphsComeFromTheAllowedSet() {
    var engine = RainEngine(columns: 30, rows: 20, profile: Intensity.inmersivo.profile, seed: 8)
    let allowed = Set(RainGlyphs.all)
    for _ in 0..<100 {
      let frame = engine.step(dt: .milliseconds(33), typing: Self.idle, textRows: [])
      #expect(frame.cells.allSatisfy { allowed.contains($0.glyph) })
    }
    #expect(allowed.contains("ｦ") && allowed.contains("ﾝ") && allowed.contains("Z"))
  }
}
