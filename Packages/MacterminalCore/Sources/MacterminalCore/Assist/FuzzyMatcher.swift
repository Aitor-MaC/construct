import Foundation

/// Resultado de una coincidencia difusa: puntuación (mayor = mejor) y rangos sobre el texto original.
public struct FuzzyMatch: Sendable, Equatable {
  public let score: Int
  public let ranges: [Range<String.Index>]

  public init(score: Int, ranges: [Range<String.Index>]) {
    self.score = score
    self.ranges = ranges
  }
}

/// Coincidencia difusa insensible a mayúsculas y diacríticos.
/// Orden de puntuación: prefijo > inicio de palabra > consecutivas > dispersas.
public enum FuzzyMatcher {
  private static let baseScore = 10
  private static let boundaryBonus = 25
  private static let consecutiveBonus = 15
  private static let gapPenalty = 2
  private static let prefixBonus = 100_000
  /// Por encima de este producto texto×consulta se usa una alineación voraz en vez de la óptima.
  private static let dynamicProgrammingBudget = 4_000_000

  /// Una unidad plegada y el carácter original del que procede.
  private struct Unit {
    let folded: Character
    let range: Range<String.Index>
    let isBoundary: Bool
  }

  public static func match(_ query: String, in text: String) -> FuzzyMatch? {
    let needle = foldedCharacters(query)
    if needle.isEmpty { return FuzzyMatch(score: 0, ranges: []) }

    let units = makeUnits(text)
    guard isSubsequence(needle, of: units) else { return nil }

    let positions: [Int]
    if units.count >= needle.count, zip(needle, units).allSatisfy({ $0 == $1.folded }) {
      positions = Array(0..<needle.count)
    } else if units.count * needle.count <= dynamicProgrammingBudget {
      positions = bestAlignment(needle, units)
    } else {
      positions = greedyAlignment(needle, units)
    }
    return FuzzyMatch(score: score(positions, units), ranges: ranges(for: positions, units))
  }

  // MARK: - Plegado

  private static func foldedCharacters(_ string: String) -> [Character] {
    var result: [Character] = []
    for character in string { result.append(contentsOf: fold(character)) }
    return result
  }

  private static func fold(_ character: Character) -> [Character] {
    if character.isASCII, let ascii = character.asciiValue {
      let lowered = (ascii >= 65 && ascii <= 90) ? ascii + 32 : ascii
      return [Character(UnicodeScalar(lowered))]
    }
    let folded = String(character).folding(
      options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    return Array(folded)
  }

  private static func makeUnits(_ text: String) -> [Unit] {
    var units: [Unit] = []
    units.reserveCapacity(text.count)
    var previousIsAlphanumeric = false
    var index = text.startIndex
    while index < text.endIndex {
      let next = text.index(after: index)
      let character = text[index]
      let isAlphanumeric = character.isLetter || character.isNumber
      let boundary = !previousIsAlphanumeric && isAlphanumeric
      for (offset, folded) in fold(character).enumerated() {
        units.append(Unit(folded: folded, range: index..<next, isBoundary: boundary && offset == 0))
      }
      previousIsAlphanumeric = isAlphanumeric
      index = next
    }
    return units
  }

  private static func isSubsequence(_ needle: [Character], of units: [Unit]) -> Bool {
    var j = 0
    for unit in units where unit.folded == needle[j] {
      j += 1
      if j == needle.count { return true }
    }
    return false
  }

  // MARK: - Alineación

  private static func greedyAlignment(_ needle: [Character], _ units: [Unit]) -> [Int] {
    var positions: [Int] = []
    var j = 0
    for (i, unit) in units.enumerated() where unit.folded == needle[j] {
      positions.append(i)
      j += 1
      if j == needle.count { break }
    }
    return positions
  }

  /// Alineación de máxima puntuación por programación dinámica, O(texto × consulta).
  private static func bestAlignment(_ needle: [Character], _ units: [Unit]) -> [Int] {
    let n = units.count
    let m = needle.count
    let unreachable = Int.min / 2
    // best[j][i]: mejor puntuación con needle[j] casada en la posición i.
    var best = [[Int]](repeating: [Int](repeating: unreachable, count: n), count: m)
    var parent = [[Int]](repeating: [Int](repeating: -1, count: n), count: m)

    for i in 0..<n where units[i].folded == needle[0] {
      best[0][i] = baseScore + (units[i].isBoundary ? boundaryBonus : 0)
    }
    if m > 1 {
      for j in 1..<m {
        // Máximo corrido de best[j-1][k] + gapPenalty*k para k <= i-2 (hueco >= 1).
        var runningBest = unreachable
        var runningIndex = -1
        for i in 0..<n {
          if i >= 2 {
            let k = i - 2
            let value = best[j - 1][k]
            if value > unreachable, value + gapPenalty * k > runningBest {
              runningBest = value + gapPenalty * k
              runningIndex = k
            }
          }
          guard units[i].folded == needle[j] else { continue }
          let gain = baseScore + (units[i].isBoundary ? boundaryBonus : 0)
          var candidate = unreachable
          var from = -1
          if i >= 1, best[j - 1][i - 1] > unreachable {
            candidate = best[j - 1][i - 1] + gain + consecutiveBonus
            from = i - 1
          }
          if runningIndex >= 0 {
            let gapped = runningBest - gapPenalty * (i - 1) + gain
            if gapped > candidate {
              candidate = gapped
              from = runningIndex
            }
          }
          if from >= 0 {
            best[j][i] = candidate
            parent[j][i] = from
          }
        }
      }
    }

    var end = -1
    var top = unreachable
    for i in 0..<n where best[m - 1][i] > top {
      top = best[m - 1][i]
      end = i
    }
    guard end >= 0 else { return greedyAlignment(needle, units) }
    var positions = [Int](repeating: 0, count: m)
    var cursor = end
    for j in stride(from: m - 1, through: 0, by: -1) {
      positions[j] = cursor
      cursor = parent[j][cursor]
    }
    return positions
  }

  private static func score(_ positions: [Int], _ units: [Unit]) -> Int {
    var total = 0
    var previous = -1
    for position in positions {
      total += baseScore
      if units[position].isBoundary { total += boundaryBonus }
      if previous >= 0 {
        if position == previous + 1 {
          total += consecutiveBonus
        } else {
          total -= gapPenalty * (position - previous - 1)
        }
      }
      previous = position
    }
    let isPrefix = positions.first == 0 && zip(positions, positions.dropFirst()).allSatisfy { $1 == $0 + 1 }
    return isPrefix ? total + prefixBonus : total
  }

  private static func ranges(for positions: [Int], _ units: [Unit]) -> [Range<String.Index>] {
    var result: [Range<String.Index>] = []
    for position in positions {
      let range = units[position].range
      if let last = result.last, last.upperBound >= range.upperBound {
        continue  // varias unidades plegadas del mismo carácter original
      }
      if let last = result.last, last.upperBound == range.lowerBound {
        result[result.count - 1] = last.lowerBound..<range.upperBound
      } else {
        result.append(range)
      }
    }
    return result
  }
}
