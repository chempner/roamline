import Foundation

enum APIError: LocalizedError {
    case invalidServer, unauthorized, server(String), invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidServer: "Enter a valid HTTPS server URL."
        case .unauthorized: "Your session expired. Please sign in again."
        case .server(let message): message
        case .invalidResponse: "The server returned an invalid response."
        }
    }
}

actor APIClient {
    private var baseURL: URL
    private var token: String?
    private let encoder: JSONEncoder = {
        let value = JSONEncoder()
        value.dateEncodingStrategy = .iso8601
        return value
    }()
    private let decoder = JSONDecoder()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 30
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    init(baseURL: URL, token: String? = nil) {
        self.baseURL = baseURL
        self.token = token
    }

    func configure(baseURL: URL, token: String?) {
        self.baseURL = baseURL
        self.token = token
    }

    func login(username: String, password: String) async throws -> LoginResponse {
        struct Body: Encodable { let username: String; let password: String; let client = "ios" }
        return try await send("/api/auth/login", method: "POST", body: Body(username: username, password: password), authenticated: false)
    }

    func me() async throws -> SessionUser {
        let response: UserResponse = try await send("/api/auth/me")
        return response.user
    }

    func trips() async throws -> [Trip] {
        let response: DashboardResponse = try await send("/api/dashboard")
        return response.trips
    }

    func trip(id: String) async throws -> Trip {
        let response: TripResponse = try await send("/api/trips/\(id)")
        return response.trip
    }

    func createTrip(_ request: CreateTripRequest) async throws -> Trip {
        let response: TripResponse = try await send("/api/trips", method: "POST", body: request)
        return response.trip
    }

    func setTripStatus(id: String, status: String) async throws -> Trip {
        struct Body: Codable { let status: String }
        let response: TripResponse = try await send("/api/trips/\(id)", method: "PATCH", body: Body(status: status))
        return response.trip
    }

    func createMoment(tripId: String, request: CreateMomentRequest) async throws -> Moment {
        let response: MomentResponse = try await send("/api/trips/\(tripId)/moments", method: "POST", body: request)
        return response.moment
    }

    func uploadPhoto(momentId: String, jpegData: Data, filename: String = "moment.jpg") async throws {
        let boundary = "Roamline-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpegData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidServer }
        components.path = (components.path as NSString).appendingPathComponent("/api/moments/\(momentId)/photos")
        guard let url = components.url else { throw APIError.invalidServer }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: responseData).error) ?? "Photo upload failed."
            throw APIError.server(message)
        }
    }

    func upload(tripId: String, points: [PendingLocation]) async throws -> SyncResponse {
        struct LocationBody: Codable {
            let id: String
            let latitude: Double
            let longitude: Double
            let altitude: Double?
            let accuracy: Double?
            let speed: Double?
            let course: Double?
            let recordedAt: String
            enum CodingKeys: String, CodingKey {
                case id, latitude, longitude, altitude, accuracy, speed, course
                case recordedAt = "recorded_at"
            }
        }
        struct Body: Codable { let points: [LocationBody] }
        let body = Body(points: points.map {
            LocationBody(id: $0.id, latitude: $0.latitude, longitude: $0.longitude,
                         altitude: $0.altitude, accuracy: $0.accuracy, speed: $0.speed,
                         course: $0.course, recordedAt: $0.recordedAt)
        })
        return try await send("/api/trips/\(tripId)/locations", method: "POST", body: body)
    }

    private func send<Response: Decodable>(_ path: String, method: String = "GET", authenticated: Bool = true) async throws -> Response {
        try await send(path, method: method, data: nil, authenticated: authenticated)
    }

    private func send<Response: Decodable, Body: Encodable>(_ path: String, method: String, body: Body, authenticated: Bool = true) async throws -> Response {
        try await send(path, method: method, data: encoder.encode(body), authenticated: authenticated)
    }

    private func send<Response: Decodable>(_ path: String, method: String, data: Data?, authenticated: Bool) async throws -> Response {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidServer }
        components.path = (components.path as NSString).appendingPathComponent(path)
        guard let url = components.url else { throw APIError.invalidServer }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = data
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if data != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authenticated, let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        if http.statusCode == 401 { throw APIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(ErrorResponse.self, from: responseData).error) ?? "Request failed (\(http.statusCode))."
            throw APIError.server(message)
        }
        do { return try decoder.decode(Response.self, from: responseData) }
        catch { throw APIError.invalidResponse }
    }
}

private struct ErrorResponse: Codable { let error: String }
