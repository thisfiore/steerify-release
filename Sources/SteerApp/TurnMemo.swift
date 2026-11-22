import Foundation
import Combine

/// Answers the views ask for again and again while the window draws once (is this session done, what is next for
/// you, which chapter is this about): worked out once, then reused until something changes.
/// Emptied whenever the app's state, a board or a session announces a change, and at the end of every turn of the
/// main run loop, so an answer is never older than the draw that asked for it.
@MainActor
enum TurnMemo {
    private final class Box { let v: Any; init(_ v: Any) { self.v = v } }
    private static var store: [String: Box] = [:]
    private static var armed = false
    private static var watched: [ObjectIdentifier: AnyCancellable] = [:]

    static func get<T>(_ key: String, _ make: () -> T) -> T {
        if let hit = store[key], let v = hit.v as? T { return v }
        let v = make()
        store[key] = Box(v)
        if !armed {
            armed = true
            DispatchQueue.main.async { store.removeAll(keepingCapacity: true); armed = false }
        }
        return v
    }
    static func clear() { if !store.isEmpty { store.removeAll(keepingCapacity: true) } }

    /// Empty the answers whenever this object is about to change (the model, a board, a session).
    static func watch<O: ObservableObject>(_ o: O) where O.ObjectWillChangePublisher == ObservableObjectPublisher {
        let id = ObjectIdentifier(o)
        guard watched[id] == nil else { return }
        watched[id] = o.objectWillChange.sink { _ in MainActor.assumeIsolated { clear() } }
    }
    /// Sessions that are gone no longer need watching.
    static func watch(sessions: [TerminalSession], boards: [BoardStore], model: AppModel) {
        var keep = Set<ObjectIdentifier>([ObjectIdentifier(model)])
        watch(model)
        for s in sessions { watch(s); keep.insert(ObjectIdentifier(s)) }
        for b in boards { watch(b); keep.insert(ObjectIdentifier(b)) }
        for k in watched.keys where !keep.contains(k) { watched[k] = nil }
    }
}
