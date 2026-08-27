const assert = require('node:assert/strict');
const test = require('node:test');
const { distanceKm, routeDistanceKm } = require('../src/geo');

test('distance uses haversine calculation', () => {
  const bern = { latitude: 46.948, longitude: 7.4474 };
  const zurich = { latitude: 47.3769, longitude: 8.5417 };
  const distance = distanceKm(bern, zurich);
  assert.ok(distance > 94 && distance < 97);
});

test('route ignores impossible GPS jumps', () => {
  const route = [
    { latitude: 46.948, longitude: 7.4474, recorded_at: '2026-01-01T10:00:00Z' },
    { latitude: 40.7128, longitude: -74.006, recorded_at: '2026-01-01T10:01:00Z' },
  ];
  assert.equal(routeDistanceKm(route), 0);
});
