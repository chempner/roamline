const EARTH_RADIUS_KM = 6371.0088;

function toRadians(value) {
  return value * Math.PI / 180;
}

function distanceKm(a, b) {
  const dLat = toRadians(b.latitude - a.latitude);
  const dLon = toRadians(b.longitude - a.longitude);
  const lat1 = toRadians(a.latitude);
  const lat2 = toRadians(b.latitude);
  const h = Math.sin(dLat / 2) ** 2
    + Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLon / 2) ** 2;
  return 2 * EARTH_RADIUS_KM * Math.asin(Math.sqrt(h));
}

function routeDistanceKm(points) {
  let total = 0;
  for (let i = 1; i < points.length; i += 1) {
    const segment = distanceKm(points[i - 1], points[i]);
    // Ignore impossible GPS jumps. At 300 km/h, 5 minutes is 25 km.
    const elapsedHours = Math.max(
      1 / 3600,
      (Date.parse(points[i].recorded_at) - Date.parse(points[i - 1].recorded_at)) / 3_600_000,
    );
    if (segment / elapsedHours <= 300) total += segment;
  }
  return Math.round(total * 10) / 10;
}

module.exports = { distanceKm, routeDistanceKm };
