const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');
const express = require('express');
const cookieParser = require('cookie-parser');
const helmet = require('helmet');
const multer = require('multer');
const { createDatabase } = require('./database');
const { routeDistanceKm } = require('./geo');
const { buildAuth } = require('./auth');

const isoNow = () => new Date().toISOString();
const id = () => crypto.randomUUID();

function validDate(value, fallback = null) {
  if (!value) return fallback;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? fallback : parsed.toISOString();
}

function text(value, max = 1000) {
  return typeof value === 'string' ? value.trim().slice(0, max) : '';
}

function createApp(options = {}) {
  const dataDir = options.dataDir || process.env.DATA_DIR
    || (process.env.NODE_ENV === 'production' ? '/data' : path.join(process.cwd(), 'data'));
  const uploadDir = path.join(dataDir, 'uploads');
  fs.mkdirSync(uploadDir, { recursive: true });
  const db = options.db || createDatabase(dataDir);
  const auth = buildAuth();
  const app = express();

  app.set('trust proxy', 1);
  app.disable('x-powered-by');
  app.use(helmet({
    contentSecurityPolicy: {
      directives: {
        defaultSrc: ["'self'"],
        imgSrc: ["'self'", 'data:', 'blob:', 'https://*.tile.openstreetmap.org'],
        styleSrc: ["'self'", "'unsafe-inline'"],
        connectSrc: ["'self'"],
      },
    },
  }));
  app.use(express.json({ limit: '2mb' }));
  app.use(cookieParser());

  app.get('/api/health', (_req, res) => res.json({ ok: true, service: 'roamline' }));
  app.post('/api/auth/login', auth.login);
  app.post('/api/auth/logout', auth.logout);
  app.get('/api/auth/me', auth.requireAuth, (req, res) => res.json({ user: req.user }));

  const upload = multer({
    storage: multer.diskStorage({
      destination: uploadDir,
      filename: (_req, file, cb) => {
        const extension = path.extname(file.originalname).toLowerCase().replace(/[^.a-z0-9]/g, '').slice(0, 8);
        cb(null, `${id()}${extension || '.jpg'}`);
      },
    }),
    limits: { fileSize: 12 * 1024 * 1024, files: 1 },
    fileFilter: (_req, file, cb) => cb(null, ['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif'].includes(file.mimetype)),
  });

  function ownedTrip(tripId, userId) {
    return db.prepare('SELECT * FROM trips WHERE id = ? AND user_id = ?').get(tripId, userId);
  }

  function serializeTrip(row, includeDetails = false, publicToken = null) {
    const points = db.prepare(
      'SELECT latitude, longitude, recorded_at FROM location_points WHERE trip_id = ? ORDER BY recorded_at',
    ).all(row.id);
    let moments = includeDetails ? db.prepare(`
      SELECT m.*, COUNT(p.id) AS photo_count
      FROM moments m LEFT JOIN photos p ON p.moment_id = m.id
      WHERE m.trip_id = ? GROUP BY m.id ORDER BY m.visited_at DESC
    `).all(row.id) : undefined;
    if (moments) {
      const photosForMoment = db.prepare('SELECT id, caption, mime_type, created_at FROM photos WHERE moment_id = ? ORDER BY created_at');
      moments = moments.map((moment) => ({
        ...moment,
        photos: photosForMoment.all(moment.id).map((photo) => ({
          ...photo,
          url: publicToken
            ? `/api/public/trips/${publicToken}/photos/${photo.id}`
            : `/api/photos/${photo.id}/file`,
        })),
      }));
    }
    const result = {
      ...row,
      distance_km: routeDistanceKm(points),
      point_count: points.length,
      moment_count: db.prepare('SELECT COUNT(*) AS count FROM moments WHERE trip_id = ?').get(row.id).count,
    };
    if (includeDetails) {
      result.route = points;
      result.moments = moments;
    }
    return result;
  }

  app.get('/api/dashboard', auth.requireAuth, (req, res) => {
    const trips = db.prepare('SELECT * FROM trips WHERE user_id = ? ORDER BY updated_at DESC').all(req.user.sub);
    const enriched = trips.map((trip) => serializeTrip(trip));
    res.json({
      trips: enriched,
      totals: {
        trips: enriched.length,
        distance_km: Math.round(enriched.reduce((sum, trip) => sum + trip.distance_km, 0) * 10) / 10,
        moments: enriched.reduce((sum, trip) => sum + trip.moment_count, 0),
        countries: 0,
      },
    });
  });

  app.get('/api/trips', auth.requireAuth, (req, res) => {
    const rows = db.prepare('SELECT * FROM trips WHERE user_id = ? ORDER BY updated_at DESC').all(req.user.sub);
    res.json({ trips: rows.map((row) => serializeTrip(row)) });
  });

  app.post('/api/trips', auth.requireAuth, (req, res) => {
    const title = text(req.body?.title, 120);
    if (!title) return res.status(400).json({ error: 'Trip title is required' });
    const now = isoNow();
    const trip = {
      id: id(), user_id: req.user.sub, title, summary: text(req.body?.summary, 2000),
      start_date: validDate(req.body?.start_date), end_date: validDate(req.body?.end_date),
      status: ['planned', 'active', 'completed'].includes(req.body?.status) ? req.body.status : 'planned',
      visibility: 'private', share_token: null, cover_photo_id: null, created_at: now, updated_at: now,
    };
    db.prepare(`INSERT INTO trips
      (id,user_id,title,summary,start_date,end_date,status,visibility,share_token,cover_photo_id,created_at,updated_at)
      VALUES (@id,@user_id,@title,@summary,@start_date,@end_date,@status,@visibility,@share_token,@cover_photo_id,@created_at,@updated_at)`
    ).run(trip);
    res.status(201).json({ trip: serializeTrip(trip, true) });
  });

  app.get('/api/trips/:tripId', auth.requireAuth, (req, res) => {
    const trip = ownedTrip(req.params.tripId, req.user.sub);
    if (!trip) return res.status(404).json({ error: 'Trip not found' });
    res.json({ trip: serializeTrip(trip, true) });
  });

  app.patch('/api/trips/:tripId', auth.requireAuth, (req, res) => {
    const current = ownedTrip(req.params.tripId, req.user.sub);
    if (!current) return res.status(404).json({ error: 'Trip not found' });
    const next = {
      ...current,
      title: req.body.title === undefined ? current.title : text(req.body.title, 120),
      summary: req.body.summary === undefined ? current.summary : text(req.body.summary, 2000),
      start_date: req.body.start_date === undefined ? current.start_date : validDate(req.body.start_date),
      end_date: req.body.end_date === undefined ? current.end_date : validDate(req.body.end_date),
      status: ['planned', 'active', 'completed'].includes(req.body.status) ? req.body.status : current.status,
      updated_at: isoNow(),
    };
    if (!next.title) return res.status(400).json({ error: 'Trip title is required' });
    db.prepare(`UPDATE trips SET title=@title, summary=@summary, start_date=@start_date,
      end_date=@end_date, status=@status, updated_at=@updated_at WHERE id=@id AND user_id=@user_id`).run(next);
    res.json({ trip: serializeTrip(next, true) });
  });

  app.delete('/api/trips/:tripId', auth.requireAuth, (req, res) => {
    const result = db.prepare('DELETE FROM trips WHERE id = ? AND user_id = ?').run(req.params.tripId, req.user.sub);
    if (!result.changes) return res.status(404).json({ error: 'Trip not found' });
    res.status(204).end();
  });

  app.post('/api/trips/:tripId/locations', auth.requireAuth, (req, res) => {
    const trip = ownedTrip(req.params.tripId, req.user.sub);
    if (!trip) return res.status(404).json({ error: 'Trip not found' });
    const points = Array.isArray(req.body?.points) ? req.body.points.slice(0, 1000) : [];
    if (!points.length) return res.status(400).json({ error: 'At least one location point is required' });
    const insert = db.prepare(`INSERT OR IGNORE INTO location_points
      (id,trip_id,user_id,latitude,longitude,altitude,accuracy,speed,course,recorded_at,created_at)
      VALUES (@id,@trip_id,@user_id,@latitude,@longitude,@altitude,@accuracy,@speed,@course,@recorded_at,@created_at)`);
    let accepted = 0;
    const transaction = db.transaction(() => {
      for (const point of points) {
        const latitude = Number(point.latitude);
        const longitude = Number(point.longitude);
        const recordedAt = validDate(point.recorded_at);
        if (!Number.isFinite(latitude) || latitude < -90 || latitude > 90
          || !Number.isFinite(longitude) || longitude < -180 || longitude > 180 || !recordedAt) continue;
        accepted += insert.run({
          id: text(point.id, 80) || id(), trip_id: trip.id, user_id: req.user.sub,
          latitude, longitude,
          altitude: Number.isFinite(Number(point.altitude)) ? Number(point.altitude) : null,
          accuracy: Number.isFinite(Number(point.accuracy)) ? Number(point.accuracy) : null,
          speed: Number.isFinite(Number(point.speed)) ? Number(point.speed) : null,
          course: Number.isFinite(Number(point.course)) ? Number(point.course) : null,
          recorded_at: recordedAt, created_at: isoNow(),
        }).changes;
      }
      db.prepare('UPDATE trips SET updated_at = ?, status = ? WHERE id = ?')
        .run(isoNow(), trip.status === 'planned' ? 'active' : trip.status, trip.id);
    });
    transaction();
    res.status(201).json({ accepted, received: points.length });
  });

  app.post('/api/trips/:tripId/moments', auth.requireAuth, (req, res) => {
    const trip = ownedTrip(req.params.tripId, req.user.sub);
    if (!trip) return res.status(404).json({ error: 'Trip not found' });
    const title = text(req.body?.title, 140);
    if (!title) return res.status(400).json({ error: 'Moment title is required' });
    const now = isoNow();
    const moment = {
      id: id(), trip_id: trip.id, user_id: req.user.sub, title,
      story: text(req.body?.story, 10_000), place: text(req.body?.place, 180),
      latitude: Number.isFinite(Number(req.body?.latitude)) ? Number(req.body.latitude) : null,
      longitude: Number.isFinite(Number(req.body?.longitude)) ? Number(req.body.longitude) : null,
      visited_at: validDate(req.body?.visited_at, now), created_at: now, updated_at: now,
    };
    db.prepare(`INSERT INTO moments
      (id,trip_id,user_id,title,story,place,latitude,longitude,visited_at,created_at,updated_at)
      VALUES (@id,@trip_id,@user_id,@title,@story,@place,@latitude,@longitude,@visited_at,@created_at,@updated_at)`
    ).run(moment);
    db.prepare('UPDATE trips SET updated_at = ? WHERE id = ?').run(now, trip.id);
    res.status(201).json({ moment: { ...moment, photo_count: 0 } });
  });

  app.patch('/api/moments/:momentId', auth.requireAuth, (req, res) => {
    const current = db.prepare('SELECT * FROM moments WHERE id = ? AND user_id = ?').get(req.params.momentId, req.user.sub);
    if (!current) return res.status(404).json({ error: 'Moment not found' });
    const next = {
      ...current,
      title: req.body.title === undefined ? current.title : text(req.body.title, 140),
      story: req.body.story === undefined ? current.story : text(req.body.story, 10_000),
      place: req.body.place === undefined ? current.place : text(req.body.place, 180),
      visited_at: req.body.visited_at === undefined ? current.visited_at : validDate(req.body.visited_at, current.visited_at),
      updated_at: isoNow(),
    };
    if (!next.title) return res.status(400).json({ error: 'Moment title is required' });
    db.prepare(`UPDATE moments SET title=@title, story=@story, place=@place,
      visited_at=@visited_at, updated_at=@updated_at WHERE id=@id AND user_id=@user_id`).run(next);
    res.json({ moment: next });
  });

  app.delete('/api/moments/:momentId', auth.requireAuth, (req, res) => {
    const result = db.prepare('DELETE FROM moments WHERE id = ? AND user_id = ?').run(req.params.momentId, req.user.sub);
    if (!result.changes) return res.status(404).json({ error: 'Moment not found' });
    res.status(204).end();
  });

  app.post('/api/moments/:momentId/photos', auth.requireAuth, upload.single('photo'), (req, res) => {
    if (!req.file) return res.status(400).json({ error: 'A supported image is required' });
    const moment = db.prepare('SELECT * FROM moments WHERE id = ? AND user_id = ?').get(req.params.momentId, req.user.sub);
    if (!moment) {
      fs.rmSync(req.file.path, { force: true });
      return res.status(404).json({ error: 'Moment not found' });
    }
    const photo = {
      id: id(), trip_id: moment.trip_id, moment_id: moment.id, user_id: req.user.sub,
      file_name: req.file.filename, original_name: text(req.file.originalname, 240), mime_type: req.file.mimetype,
      caption: text(req.body?.caption, 500), created_at: isoNow(),
    };
    db.prepare(`INSERT INTO photos
      (id,trip_id,moment_id,user_id,file_name,original_name,mime_type,caption,created_at)
      VALUES (@id,@trip_id,@moment_id,@user_id,@file_name,@original_name,@mime_type,@caption,@created_at)`
    ).run(photo);
    res.status(201).json({ photo: { ...photo, url: `/api/photos/${photo.id}/file` } });
  });

  app.get('/api/photos/:photoId/file', auth.requireAuth, (req, res) => {
    const photo = db.prepare('SELECT * FROM photos WHERE id = ? AND user_id = ?').get(req.params.photoId, req.user.sub);
    if (!photo) return res.status(404).json({ error: 'Photo not found' });
    res.type(photo.mime_type).sendFile(path.join(uploadDir, photo.file_name));
  });

  app.post('/api/trips/:tripId/share', auth.requireAuth, (req, res) => {
    const trip = ownedTrip(req.params.tripId, req.user.sub);
    if (!trip) return res.status(404).json({ error: 'Trip not found' });
    const enabled = req.body?.enabled !== false;
    const token = enabled ? (trip.share_token || crypto.randomBytes(18).toString('base64url')) : null;
    db.prepare('UPDATE trips SET visibility = ?, share_token = ?, updated_at = ? WHERE id = ?')
      .run(enabled ? 'shared' : 'private', token, isoNow(), trip.id);
    res.json({ enabled, share_token: token, share_path: token ? `/shared/${token}` : null });
  });

  app.get('/api/trips/:tripId/export.geojson', auth.requireAuth, (req, res) => {
    const trip = ownedTrip(req.params.tripId, req.user.sub);
    if (!trip) return res.status(404).json({ error: 'Trip not found' });
    const points = db.prepare('SELECT * FROM location_points WHERE trip_id = ? ORDER BY recorded_at').all(trip.id);
    const moments = db.prepare('SELECT * FROM moments WHERE trip_id = ? ORDER BY visited_at').all(trip.id);
    const features = [];
    if (points.length) features.push({
      type: 'Feature', properties: { name: trip.title, timestamps: points.map((p) => p.recorded_at) },
      geometry: { type: 'LineString', coordinates: points.map((p) => [p.longitude, p.latitude, p.altitude].filter((v) => v != null)) },
    });
    features.push(...moments.filter((m) => m.latitude != null && m.longitude != null).map((m) => ({
      type: 'Feature', properties: { name: m.title, description: m.story, place: m.place, visited_at: m.visited_at },
      geometry: { type: 'Point', coordinates: [m.longitude, m.latitude] },
    })));
    res.attachment(`${trip.title.replace(/[^a-z0-9]+/gi, '-').toLowerCase() || 'trip'}.geojson`);
    res.json({ type: 'FeatureCollection', features });
  });

  app.get('/api/public/trips/:shareToken', (req, res) => {
    const trip = db.prepare("SELECT * FROM trips WHERE share_token = ? AND visibility = 'shared'").get(req.params.shareToken);
    if (!trip) return res.status(404).json({ error: 'Shared trip not found' });
    const safeTrip = serializeTrip(trip, true, req.params.shareToken);
    delete safeTrip.user_id;
    delete safeTrip.share_token;
    res.json({ trip: safeTrip });
  });

  app.get('/api/public/trips/:shareToken/photos/:photoId', (req, res) => {
    const photo = db.prepare(`
      SELECT p.* FROM photos p JOIN trips t ON t.id = p.trip_id
      WHERE p.id = ? AND t.share_token = ? AND t.visibility = 'shared'
    `).get(req.params.photoId, req.params.shareToken);
    if (!photo) return res.status(404).json({ error: 'Shared photo not found' });
    res.type(photo.mime_type).sendFile(path.join(uploadDir, photo.file_name));
  });

  app.get('/api/settings', auth.requireAuth, (req, res) => {
    const settings = db.prepare('SELECT * FROM user_settings WHERE user_id = ?').get(req.user.sub)
      || { user_id: req.user.sub, distance_unit: 'km', tracking_precision: 'balanced' };
    res.json({ settings });
  });

  app.put('/api/settings', auth.requireAuth, (req, res) => {
    const settings = {
      user_id: req.user.sub,
      distance_unit: req.body?.distance_unit === 'mi' ? 'mi' : 'km',
      tracking_precision: ['battery', 'balanced', 'precise'].includes(req.body?.tracking_precision)
        ? req.body.tracking_precision : 'balanced',
      updated_at: isoNow(),
    };
    db.prepare(`INSERT INTO user_settings (user_id,distance_unit,tracking_precision,updated_at)
      VALUES (@user_id,@distance_unit,@tracking_precision,@updated_at)
      ON CONFLICT(user_id) DO UPDATE SET distance_unit=excluded.distance_unit,
      tracking_precision=excluded.tracking_precision,updated_at=excluded.updated_at`).run(settings);
    res.json({ settings });
  });

  const frontendDir = options.frontendDir || process.env.FRONTEND_DIR
    || path.join(__dirname, '..', '..', 'frontend', 'dist');
  if (fs.existsSync(frontendDir)) {
    app.use(express.static(frontendDir, { maxAge: '1h', index: false }));
    app.get(/^(?!\/api).*/, (_req, res) => res.sendFile(path.join(frontendDir, 'index.html')));
  }

  app.use((error, _req, res, _next) => {
    console.error(error);
    if (error instanceof multer.MulterError) return res.status(400).json({ error: error.message });
    return res.status(500).json({ error: 'Unexpected server error' });
  });

  app.locals.db = db;
  return app;
}

module.exports = { createApp };
