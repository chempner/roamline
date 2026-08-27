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

    func nextBatch(limit: Int = 200) -> [PendingLocation] {
        guard let tripId = points.first?.tripId else { return [] }
        return Array(points.lazy.filter { $0.tripId == tripId }.prefix(limit))
    }

    func remove(ids: Set<String>) {
        points.removeAll { ids.contains($0.id) }
        persist()
    }

    func count() -> Int { points.count }

    private func persist() {
        guard let data = try? JSONEncoder().encode(points) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
