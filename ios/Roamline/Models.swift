import Foundation

struct SessionUser: Codable, Equatable {
    let sub: String?
    let username: String
    let displayName: String?
    let isAdmin: Bool?

    enum CodingKeys: String, CodingKey {
        case sub, username
        case displayName = "display_name"
        case isAdmin = "is_admin"
    }
}

struct Trip: Codable, Identifiable, Hashable {
    let id: String
    let userId: String?
    var title: String
    var summary: String
    var startDate: String?
    var endDate: String?
    var status: String
    var visibility: String
    var shareToken: String?
    var distanceKm: Double
    var pointCount: Int
    var momentCount: Int
    var route: [RoutePoint]?
    var moments: [Moment]?

    enum CodingKeys: String, CodingKey {
        case id, title, summary, status, visibility, route, moments
        case userId = "user_id"
        case startDate = "start_date"
        case endDate = "end_date"
        case shareToken = "share_token"
        case distanceKm = "distance_km"
        case pointCount = "point_count"
        case momentCount = "moment_count"
    }
}

struct RoutePoint: Codable, Hashable {
    let latitude: Double
    let longitude: Double
    let recordedAt: String

    enum CodingKeys: String, CodingKey {
        case latitude, longitude
        case recordedAt = "recorded_at"
    }
}

struct Moment: Codable, Identifiable, Hashable {
    let id: String
    let tripId: String
    var title: String
    var story: String
    var place: String
    var latitude: Double?
    var longitude: Double?
    var visitedAt: String
    var photoCount: Int?
    var photos: [MomentPhoto]?

    enum CodingKeys: String, CodingKey {
        case id, title, story, place, latitude, longitude, photos
        case tripId = "trip_id"
        case visitedAt = "visited_at"
        case photoCount = "photo_count"
    }
}

struct MomentPhoto: Codable, Identifiable, Hashable {
    let id: String
    let caption: String
    let mimeType: String
    let url: String
    enum CodingKeys: String, CodingKey {
        case id, caption, url
        case mimeType = "mime_type"
    }
}

struct PendingLocation: Codable, Identifiable, Hashable {
    let id: String
    let tripId: String
    let latitude: Double
    let longitude: Double
    let altitude: Double?
    let accuracy: Double?
    let speed: Double?
    let course: Double?
    let recordedAt: String
    // Username of the account that queued the point. Optional so queue files written by
    // older app versions still decode; nil-owner points remain flushable by any user.
    let owner: String?

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, altitude, accuracy, speed, course, owner
        case tripId = "trip_id"
        case recordedAt = "recorded_at"
    }
}

struct DashboardResponse: Codable { let trips: [Trip] }
struct TripResponse: Codable { let trip: Trip }
struct MomentResponse: Codable { let moment: Moment }
struct PhotoUploadResponse: Codable { let photo: MomentPhoto }
struct UserResponse: Codable { let user: SessionUser }
struct LoginResponse: Codable {
    let token: String?
    let username: String?
    let displayName: String?
    let isAdmin: Bool?
    let mustChangePassword: Bool?
    enum CodingKeys: String, CodingKey {
        case token, username
        case displayName = "display_name"
        case isAdmin = "is_admin"
        case mustChangePassword = "must_change_password"
    }
}
struct SyncResponse: Codable { let accepted: Int; let received: Int }

struct CreateTripRequest: Codable {
    let title: String
    let summary: String
    let startDate: String?
    let endDate: String?
    let status: String
    enum CodingKeys: String, CodingKey {
        case title, summary, status
        case startDate = "start_date"
        case endDate = "end_date"
    }
}

struct CreateMomentRequest: Codable {
    let title: String
    let story: String
    let place: String
    let latitude: Double?
    let longitude: Double?
    let visitedAt: String
    enum CodingKeys: String, CodingKey {
        case title, story, place, latitude, longitude
        case visitedAt = "visited_at"
    }
}
