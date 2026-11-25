import Foundation

public enum BlockStep: Sendable { case previous, next }

/// Bloque al que saltar y fila absoluta de su prompt.
public struct BlockTarget: Sendable, Equatable {
  public let id: UUID
  public let row: Int
  public init(id: UUID, row: Int) {
    self.id = id
    self.row = row
  }
}

/// ⌘↑/⌘↓ entre comandos. El prompt en edición no es navegable.
public enum BlockNavigation {
  /// Sin selección (o si el bloque seleccionado ya no está), ⌘↑ parte del borde inferior de la
  /// vista —el último comando si se está abajo del todo— y ⌘↓ no hace nada.
  @MainActor public static func target(
    _ step: BlockStep, from selected: UUID?, in tracker: BlockTracker, viewportBottom: Int,
    resolve: (RowAnchor) -> Int?
  ) -> BlockTarget? {
    let selectedRow = selected.flatMap { id in
      tracker.blocks.first { $0.id == id }.flatMap { resolve($0.promptAnchor) }
    }
    switch step {
    case .previous:
      var reference = selectedRow ?? viewportBottom
      while let candidate = tracker.block(before: reference, resolve: resolve),
        let row = resolve(candidate.promptAnchor)
      {
        if candidate.state != .editing { return BlockTarget(id: candidate.id, row: row) }
        reference = row
      }
      return nil
    case .next:
      guard let selectedRow,
        let candidate = tracker.block(after: selectedRow, resolve: resolve),
        candidate.state != .editing, let row = resolve(candidate.promptAnchor)
      else { return nil }
      return BlockTarget(id: candidate.id, row: row)
    }
  }
}
