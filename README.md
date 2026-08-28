# Roamline

Roamline is a self-hosted travel tracker and journal inspired by the map-and-timeline experience of Polarsteps. It keeps the product, code, and data independent: this is not a Polarsteps client or clone.

The repository contains the complete stack:

- a responsive React web app with route maps, trips, moments, photos, sharing, and GeoJSON export;
- a Node/Express API with per-user authorization and a SQLite database;
- a native SwiftUI iOS app with explicit background GPS tracking, offline point storage, batched sync, trip maps, journal moments, and photo uploads;
- a single multi-architecture Docker image and TrueNAS compose file;
- shared authentication through the existing `AuthService` JWT pattern.

## How it fits together

```text
iPhone (Core Location) ─┐
                        ├── HTTPS ── Roamline container ── /data/roamline.db
Web browser ────────────┘               │                └─ /data/uploads
                                        └── AuthService (login/access checks)
```

GPS points are written to an on-device queue before upload. Each point has a stable UUID and the API uses idempotent inserts, so retrying a batch cannot duplicate the route. Tracking runs only after the user starts it and stops immediately when the user taps Stop.

## Features

- private trips in planning, active, and completed stages;
- background GPS capture with 25 m distance filtering and accuracy rejection;
- offline-first route queue and automatic retry;
- map route, distance, date, and moment statistics;
- journal moments with place, story, time, coordinate, and photo;
- revocable read-only sharing links;
- GeoJSON route and waypoint export;
- users isolated by the AuthService JWT subject;
- SQLite WAL mode for safe, simple backups;
- health check, graceful shutdown, non-root container, and GHCR publishing.

## Local development

Requirements: Node.js 22 and npm.

```bash
npm install
npm run install:all
AUTH_DISABLED=true npm run dev
```

Open `http://localhost:5173`. The backend is on `http://localhost:3001`; Vite proxies `/api` requests to it. Development data is stored under `backend/data` or the directory from `DATA_DIR`.

Run the checks:

```bash
npm test
npm run build
```

Run the production image locally without AuthService:

```bash
docker compose -f docker-compose.build.yml up --build
```

Then open `http://localhost:5026`.

## AuthService integration

`AuthService/server.js` in the adjacent repository has been registered with:

```js
roamline: {
  label: 'Roamline',
  roles: null,
},
```

Rebuild/redeploy AuthService before enabling real login. Admins receive the new app automatically. For non-admin users, enable **Roamline** in the AuthService admin page.

Users with an older session should sign out and back in once after the AuthService update so their JWT reflects the new app list.

Roamline requires the exact same `JWT_SECRET` as AuthService. It sends `app: "roamline"` during login and current-session checks, so removing a user's permission revokes their access.

## Publish the image

Create the GitHub repository and push `main`. The workflow tests the API, builds the web app, and publishes AMD64 and ARM64 images to:

```text
ghcr.io/chempner/roamline:latest
```

If the repository owner/name differs, update the `image:` value in both compose files. The workflow itself automatically uses the actual GitHub repository name.

## TrueNAS deployment

1. Create the persistent dataset and make it writable by container UID/GID `1000`:

   ```bash
   mkdir -p /mnt/SSD/Apps/Roamline/uploads
   chown -R 1000:1000 /mnt/SSD/Apps/Roamline
   ```

2. Put `docker-compose.truenas.yml` and an `.env` file in the TrueNAS app directory. At minimum:

   ```dotenv
   JWT_SECRET=the-exact-secret-used-by-authservice
   AUTH_SERVICE_URL=http://10.13.37.11:3100
   ROAMLINE_PORT=5026
   ROAMLINE_DATA_PATH=/mnt/SSD/Apps/Roamline
   SECURE_COOKIES=true
   ```

3. Start the app:

   ```bash
   docker compose -f docker-compose.truenas.yml pull
   docker compose -f docker-compose.truenas.yml up -d
   ```

4. Copy `deploy/traefik/roamline.yml` into the Traefik dynamic configuration directory and adjust the hostname, certificate resolver, or TrueNAS IP if needed.

The web app will be available on port `5026` and, with the included example, at `https://roamline.chempner.ch`. If you use the app directly over plain HTTP, set `SECURE_COOKIES=false`. Keep it `true` behind HTTPS.

### Updating

```bash
docker compose -f docker-compose.truenas.yml pull
docker compose -f docker-compose.truenas.yml up -d
```

The `wud.watch=true` label matches the other self-hosted apps.

### Backup

Stop the container or use SQLite's backup API before copying a live database. A simple cold backup is:

```bash
docker compose -f docker-compose.truenas.yml stop
tar -C /mnt/SSD/Apps -czf roamline-backup.tgz Roamline
docker compose -f docker-compose.truenas.yml start
```

Both `roamline.db` and `uploads/` are required for a complete restore.

## iOS app

The generated Xcode project is committed at `ios/Roamline.xcodeproj`. To regenerate it after changing `project.yml`:

```bash
cd ios
xcodegen generate
open Roamline.xcodeproj
```

In Xcode:

1. select the Roamline target and choose your Apple Developer team;
2. change `PRODUCT_BUNDLE_IDENTIFIER` if `ch.chempner.roamline` is unavailable;
3. run on a real iPhone to test background location;
4. sign in and set the public HTTPS URL of the server.

iOS deliberately accepts HTTPS servers only (plus localhost for simulator development). A trusted TLS certificate is required on a real device. The app requests **Always** location access when tracking starts and has the `location` background mode. App Store submission will require an accurate privacy policy and a clear explanation of the user-started tracking feature.

## Important privacy behavior

- Trips are private by default.
- A trip becomes public only after a sharing link is enabled.
- Disabling sharing invalidates the URL immediately.
- The iOS token is stored in Keychain with `AfterFirstUnlockThisDeviceOnly` protection.
- The iOS app never starts GPS tracking just because it launched.
- Unsynced points remain in Application Support across app restarts.
- Uploaded images and GPS coordinates remain on the self-hosted server.

Map tiles are loaded from OpenStreetMap. For heavy or public use, configure a dedicated tile provider rather than relying on the community tile endpoint.

## API overview

All endpoints except health and shared-trip reads require an AuthService cookie or Bearer token.

| Endpoint | Purpose |
| --- | --- |
| `GET /api/health` | Container health |
| `POST /api/auth/login` | AuthService login proxy |
| `GET /api/dashboard` | Trips and totals |
| `POST /api/trips` | Create a trip |
| `POST /api/trips/:id/locations` | Upload up to 1,000 GPS points |
| `POST /api/trips/:id/moments` | Add a journal moment |
| `POST /api/moments/:id/photos` | Upload one image |
| `POST /api/trips/:id/share` | Enable or revoke sharing |
| `GET /api/trips/:id/export.geojson` | Export route and waypoints |

## Repository layout

```text
backend/        Express API, SQLite schema, auth, tests
frontend/       Responsive React/Vite web app
ios/            Native SwiftUI app and XcodeGen definition
deploy/         Reverse-proxy example
.github/        Test/build/GHCR workflow
```
