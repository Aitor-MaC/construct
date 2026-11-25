import MacterminalCore
import MacterminalTerminal

extension BlocksOverlayView {
  /// ⌘↑/⌘↓ sobre el panel con foco: seleccionan el bloque anterior/siguiente y, si su prompt no
  /// se ve, desplazan la vista a esa fila, sin animación. Sin destino quedan deshabilitadas.
  /// `state` devuelve el `BlockOverlayState` del panel (T14 guarda uno por panel).
  static func registerActions(
    in registry: ActionRegistry, state: @escaping (TerminalPaneController) -> BlockOverlayState?
  ) {
    let steps: [(TerminalAction, BlockStep)] = [(.previousBlock, .previous), (.nextBlock, .next)]
    for (action, step) in steps {
      registry.register(
        action, isEnabled: { navigation(step, in: $0, state: state) != nil },
        handler: { context in
          guard let navigation = navigation(step, in: context, state: state) else { return }
          navigation.selection.select(navigation.target.id)
          if !navigation.visibleRows.contains(navigation.target.row) {
            navigation.pane.scroll(toRow: navigation.target.row)
          }
        })
    }
    registry.register(
      .copyBlockCommand,
      isEnabled: { selected(in: $0, state: state).map { $0.actions.command(of: $0.block) != nil } ?? false },
      handler: { context in
        guard let selected = selected(in: context, state: state) else { return }
        selected.actions.copyCommand(selected.block)
      })
    registry.register(
      .copyBlockOutput,
      isEnabled: { selected(in: $0, state: state).map { $0.actions.canCopyOutput($0.block) } ?? false },
      handler: { context in
        guard let selected = selected(in: context, state: state) else { return }
        selected.actions.copyOutput(selected.block)
      })
  }

  /// El bloque seleccionado con ⌘↑/⌘↓ en el panel con foco, con sus acciones.
  private static func selected(
    in context: ActionContext, state: (TerminalPaneController) -> BlockOverlayState?
  ) -> (block: CommandBlock, actions: BlockActions)? {
    guard let pane = context.focusedPane, let id = state(pane)?.selectedID,
      let block = pane.blocks.blocks.last(where: { $0.id == id })
    else { return nil }
    let actions = BlockActions(
      tracker: pane.blocks, resolve: pane.resolve, textProvider: pane.text(rows:),
      insertIntoPrompt: { [weak pane] text, token in pane?.insertIntoPrompt(text, token: token) ?? .stale },
      toasts: .shared)
    return (block, actions)
  }

  private static func navigation(
    _ step: BlockStep, in context: ActionContext,
    state: (TerminalPaneController) -> BlockOverlayState?
  ) -> (pane: TerminalPaneController, selection: BlockOverlayState, target: BlockTarget, visibleRows: Range<Int>)? {
    guard let pane = context.focusedPane, let selection = state(pane),
      let viewport = pane.viewportSnapshot()
    else { return nil }
    let visibleRows = BlockGeometry(viewport: viewport).visibleRows
    guard
      let target = BlockNavigation.target(
        step, from: selection.selectedID, in: pane.blocks, viewportBottom: visibleRows.upperBound,
        resolve: pane.resolve)
    else { return nil }
    return (pane, selection, target, visibleRows)
  }
}
