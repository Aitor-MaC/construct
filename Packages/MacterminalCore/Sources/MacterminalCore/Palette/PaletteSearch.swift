import Foundation

/// Filtro difuso de la paleta: grupos en orden fijo; dentro de cada uno, mejor puntuación primero.
public enum PaletteSearch {
  private struct Scored {
    let match: PaletteMatch
    let score: Int
    let order: Int
  }

  public static func filter(_ items: [PaletteItem], query: String) -> [PaletteMatch] {
    let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
    var scored: [Scored] = []
    for (order, item) in items.enumerated() {
      if needle.isEmpty {
        scored.append(Scored(match: PaletteMatch(item: item, ranges: []), score: 0, order: order))
      } else if let fuzzy = FuzzyMatcher.match(needle, in: item.title) {
        scored.append(
          Scored(match: PaletteMatch(item: item, ranges: fuzzy.ranges), score: fuzzy.score, order: order))
      }
    }
    scored.sort(by: precedes)
    return scored.map(\.match)
  }

  private static func precedes(_ lhs: Scored, _ rhs: Scored) -> Bool {
    let (left, right) = (lhs.match.item.group, rhs.match.item.group)
    if left != right { return left < right }
    if lhs.score != rhs.score { return lhs.score > rhs.score }
    return lhs.order < rhs.order
  }
}
