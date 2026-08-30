const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { after, before, test } = require('node:test');

process.env.AUTH_DISABLED = 'true';
const { createApp } = require('../src/app');

let app;
let server;
let baseUrl;
let dataDir;

before(async () => {
  dataDir = fs.mkdtempSync(path.join(os.tmpdir(), 'roamline-test-'));
  const frontendDir = path.join(dataDir, 'frontend');
  fs.mkdirSync(frontendDir);
  fs.writeFileSync(path.join(frontendDir, 'index.html'), '<!doctype html><title>Roamline test UI</title>');
  app = createApp({ dataDir, frontendDir });
  await new Promise((resolve) => {
    server = app.listen(0, '127.0.0.1', resolve);
  });
  baseUrl = `http://127.0.0.1:${server.address().port}`;
});

after(async () => {
  await new Promise((resolve) => server.close(resolve));
  app.locals.db.close();
  fs.rmSync(dataDir, { recursive: true, force: true });
});

async function request(route, options = {}, user = 'alice') {
  const response = await fetch(`${baseUrl}${route}`, {
    ...options,
    headers: {
      ...(options.body instanceof FormData ? {} : { 'content-type': 'application/json' }),
      'x-dev-user': user,
      ...(options.headers || {}),
    },
  });
  const body = response.status === 204 ? null : await response.json();
  return { response, body };
}

test('health endpoint is public', async () => {
  const { response, body } = await request('/api/health');
  assert.equal(response.status, 200);
  assert.equal(body.ok, true);
});

test('production frontend is served at the root path', async () => {
  const response = await fetch(`${baseUrl}/`);
  assert.equal(response.status, 200);
  assert.match(await response.text(), /Roamline test UI/);
});

test('trip lifecycle, idempotent location sync, and user isolation', async () => {
  const created = await request('/api/trips', {
    method: 'POST',
    body: JSON.stringify({ title: 'Alpine Loop', status: 'planned' }),
  });
  assert.equal(created.response.status, 201);
  const tripId = created.body.trip.id;

  const points = [
    { id: 'p1', latitude: 46.948, longitude: 7.4474, recorded_at: '2026-08-01T10:00:00Z' },
    { id: 'p2', latitude: 46.958, longitude: 7.4574, recorded_at: '2026-08-01T10:15:00Z' },
  ];
  const firstSync = await request(`/api/trips/${tripId}/locations`, {
    method: 'POST', body: JSON.stringify({ points }),
  });
  assert.equal(firstSync.response.status, 201);
  assert.equal(firstSync.body.accepted, 2);

  const secondSync = await request(`/api/trips/${tripId}/locations`, {
    method: 'POST', body: JSON.stringify({ points }),
  });
  assert.equal(secondSync.body.accepted, 0);

  const detail = await request(`/api/trips/${tripId}`);
  assert.equal(detail.body.trip.point_count, 2);
  assert.ok(detail.body.trip.distance_km > 0);
  assert.equal(detail.body.trip.status, 'active');

  const forbidden = await request(`/api/trips/${tripId}`, {}, 'bob');
  assert.equal(forbidden.response.status, 404);

  // The same client-supplied point ids must not collide with another trip.
  const otherTrip = await request('/api/trips', {
    method: 'POST', body: JSON.stringify({ title: 'Second Loop' }),
  });
  const otherSync = await request(`/api/trips/${otherTrip.body.trip.id}/locations`, {
    method: 'POST', body: JSON.stringify({ points }),
  });
  assert.equal(otherSync.body.accepted, 2);
});

test('moments, public sharing, and GeoJSON export work', async () => {
  const created = await request('/api/trips', {
    method: 'POST', body: JSON.stringify({ title: 'Coastal Train' }),
  });
  const tripId = created.body.trip.id;

  const moment = await request(`/api/trips/${tripId}/moments`, {
    method: 'POST',
    body: JSON.stringify({
      title: 'Morning in town', story: 'Coffee beside the station.', place: 'Lugano',
      latitude: 46.0037, longitude: 8.9511, visited_at: '2026-08-10T08:00:00Z',
    }),
  });
  assert.equal(moment.response.status, 201);

  const uploadBody = new FormData();
  uploadBody.append('photo', new Blob([new Uint8Array([0xff, 0xd8, 0xff, 0xd9])], { type: 'image/jpeg' }), 'tiny.jpg');
  const uploaded = await request(`/api/moments/${moment.body.moment.id}/photos`, {
    method: 'POST', body: uploadBody,
  });
  assert.equal(uploaded.response.status, 201);

  const shared = await request(`/api/trips/${tripId}/share`, {
    method: 'POST', body: JSON.stringify({ enabled: true }),
  });
  assert.ok(shared.body.share_token);

  const publicTrip = await request(`/api/public/trips/${shared.body.share_token}`, {}, 'anonymous');
  assert.equal(publicTrip.response.status, 200);
  assert.equal(publicTrip.body.trip.moments[0].title, 'Morning in town');
  assert.equal(publicTrip.body.trip.moments[0].photos.length, 1);
  assert.equal(publicTrip.body.trip.user_id, undefined);
  for (const publicMoment of publicTrip.body.trip.moments) {
    assert.equal(publicMoment.user_id, undefined);
  }

  const publicPhoto = await fetch(`${baseUrl}${publicTrip.body.trip.moments[0].photos[0].url}`);
  assert.equal(publicPhoto.status, 200);
  assert.equal(publicPhoto.headers.get('content-type'), 'image/jpeg');

  const exported = await request(`/api/trips/${tripId}/export.geojson`);
  assert.equal(exported.body.type, 'FeatureCollection');
  assert.equal(exported.body.features[0].geometry.type, 'Point');
});
