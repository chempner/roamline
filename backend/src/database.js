const fs = require('node:fs');
const path = require('node:path');
const Database = require('better-sqlite3');

function createDatabase(dataDir = process.env.DATA_DIR || '/data') {
  fs.mkdirSync(dataDir, { recursive: true });
  const db = new Database(path.join(dataDir, 'roamline.db'));
  db.pragma('journal_mode = WAL');
  db.pragma('foreign_keys = ON');
  db.pragma('busy_timeout = 5000');

  db.exec(`
    CREATE TABLE IF NOT EXISTS trips (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      summary TEXT NOT NULL DEFAULT '',
      start_date TEXT,
      end_date TEXT,
      status TEXT NOT NULL DEFAULT 'planned' CHECK(status IN ('planned','active','completed')),
      visibility TEXT NOT NULL DEFAULT 'private' CHECK(visibility IN ('private','shared')),
      share_token TEXT UNIQUE,
      cover_photo_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS location_points (
      id TEXT NOT NULL,
      trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL,
      latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
      longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180),
      altitude REAL,
      accuracy REAL,
      speed REAL,
      course REAL,
      recorded_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (trip_id, id)
    );

    CREATE TABLE IF NOT EXISTS moments (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL,
      title TEXT NOT NULL,
      story TEXT NOT NULL DEFAULT '',
      place TEXT NOT NULL DEFAULT '',
      latitude REAL,
      longitude REAL,
      visited_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS photos (
      id TEXT PRIMARY KEY,
      trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
      moment_id TEXT REFERENCES moments(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL,
      file_name TEXT NOT NULL,
      original_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      caption TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS user_settings (
      user_id TEXT PRIMARY KEY,
      distance_unit TEXT NOT NULL DEFAULT 'km' CHECK(distance_unit IN ('km','mi')),
      tracking_precision TEXT NOT NULL DEFAULT 'balanced' CHECK(tracking_precision IN ('battery','balanced','precise')),
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_trips_user_updated ON trips(user_id, updated_at DESC);
    CREATE INDEX IF NOT EXISTS idx_locations_trip_time ON location_points(trip_id, recorded_at);
    CREATE INDEX IF NOT EXISTS idx_moments_trip_time ON moments(trip_id, visited_at DESC);
    CREATE INDEX IF NOT EXISTS idx_photos_moment ON photos(moment_id, created_at);
  `);

  // Older databases used a global id primary key on location_points, so identical
  // client-supplied ids collided across trips. SQLite cannot alter a primary key,
  // so rebuild the table with the composite (trip_id, id) key.
  const pointKeyColumns = db.pragma('table_info(location_points)').filter((column) => column.pk > 0);
  if (pointKeyColumns.length === 1) {
    db.exec(`
      BEGIN;
      CREATE TABLE location_points_migrated (
        id TEXT NOT NULL,
        trip_id TEXT NOT NULL REFERENCES trips(id) ON DELETE CASCADE,
        user_id TEXT NOT NULL,
        latitude REAL NOT NULL CHECK(latitude BETWEEN -90 AND 90),
        longitude REAL NOT NULL CHECK(longitude BETWEEN -180 AND 180),
        altitude REAL,
        accuracy REAL,
        speed REAL,
        course REAL,
        recorded_at TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (trip_id, id)
      );
      INSERT INTO location_points_migrated
        SELECT id,trip_id,user_id,latitude,longitude,altitude,accuracy,speed,course,recorded_at,created_at
        FROM location_points;
      DROP TABLE location_points;
      ALTER TABLE location_points_migrated RENAME TO location_points;
      CREATE INDEX IF NOT EXISTS idx_locations_trip_time ON location_points(trip_id, recorded_at);
      COMMIT;
    `);
  }

  return db;
}

module.exports = { createDatabase };
