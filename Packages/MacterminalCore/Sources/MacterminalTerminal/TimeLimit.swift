import Synchronization

/// Carrera "lo primero que llegue" entre una operación y un tiempo límite. A diferencia de un
/// `TaskGroup`, que siempre espera a todas sus hijas, aquí la perdedora se cancela y no se espera:
/// una operación que no atiende la cancelación (una escritura síncrona en un disco lento) no
/// alarga la respuesta más allá del límite.
public enum TimeLimit {
  /// `sleep` es el reloj del límite (los tests lo sustituyen). Cancelar al llamador cancela la
  /// operación; el límite sigue en pie por si la operación no lo atiende.
  public static func run<T: Sendable>(
    limit: Duration,
    sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    operation: @escaping @Sendable () async -> T,
    onTimeout: @escaping @Sendable () -> T
  ) async -> T {
    let race = Race<T>()
    return await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        race.start(
          continuation,
          work: Task { race.finish(with: await operation()) },
          timer: Task {
            do { try await sleep(limit) } catch { return }
            race.finish(with: onTimeout())
          })
      }
    } onCancel: {
      race.cancelWork()
    }
  }
}

/// La continuación se reanuda una sola vez, con el primer resultado que llegue.
private final class Race<T: Sendable>: Sendable {
  private struct State {
    var continuation: CheckedContinuation<T, Never>?
    var result: T?
    var work: Task<Void, Never>?
    var timer: Task<Void, Never>?
    var isCancelled = false
  }
  private let state = Mutex(State())

  func start(
    _ continuation: CheckedContinuation<T, Never>, work: Task<Void, Never>, timer: Task<Void, Never>
  ) {
    // Una tarea puede acabar antes de que se guarde la continuación: su resultado espera aquí.
    let early: T? = state.withLock { state in
      state.work = work
      state.timer = timer
      if state.isCancelled { work.cancel() }
      guard let result = state.result else {
        state.continuation = continuation
        return nil
      }
      return result
    }
    guard let early else { return }
    work.cancel()
    timer.cancel()
    continuation.resume(returning: early)
  }

  func finish(with value: T) {
    let winner = state.withLock { state -> (CheckedContinuation<T, Never>?, [Task<Void, Never>])? in
      guard state.result == nil else { return nil }
      state.result = value
      let losers = [state.work, state.timer].compactMap { $0 }
      defer { state.continuation = nil }
      return (state.continuation, losers)
    }
    guard let (continuation, losers) = winner else { return }
    for task in losers { task.cancel() }
    continuation?.resume(returning: value)
  }

  func cancelWork() {
    let work = state.withLock { state in
      state.isCancelled = true
      return state.work
    }
    work?.cancel()
  }
}
