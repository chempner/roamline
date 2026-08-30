import Foundation

actor OfflinePointStore {
    private let fileURL: URL
    private var points: [PendingLocation]

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("Roamline", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        fileURL = directory.appendingPathComponent("pending-locations.json")
        points = (try? Data(contentsOf: fileURL)).flatMap { try? JSONDecoder().decode([PendingLocation].self, from: $0) } ?? []
    }

    func append(_ point: PendingLocation) {
        guard !points.contains(where: { $0.id == point.id }) else { return }
        points.append(point)
        persist()
    }

    func nextBatch(limit: Int = 200, owner: String?) -> [PendingLocation] {
        guard let tripId = points.first(where: { isFlushable($0, by: owner) })?.tripId else { return [] }
        return Array(points.lazy.filter { $0.tripId == tripId && self.isFlushable($0, by: owner) }.prefix(limit))
    }

    func remove(ids: Set<String>) {
        points.removeAll { ids.contains($0.id) }
        persist()
    }

    func removeAll(tripId: String, owner: String?) {
        points.removeAll { $0.tripId == tripId && isFlushable($0, by: owner) }
        persist()
    }

    func count() -> Int { points.count }

    // Points queued by older app versions carry no owner and stay flushable by any user;
    // owned points may only be uploaded or dropped by the account that captured them.
    private func isFlushable(_ point: PendingLocation, by owner: String?) -> Bool {
        point.owner == nil || point.owner == owner
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(points) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
