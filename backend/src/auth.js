const jwt = require('jsonwebtoken');

const APP_NAME = 'roamline';
const SESSION_MAX_AGE_MS = 30 * 24 * 60 * 60 * 1000;
const SESSION_CACHE_MAX_ENTRIES = 1000;

function isSecureRequest(req) {
  if (process.env.SECURE_COOKIES === 'true') return true;
  if (process.env.SECURE_COOKIES === 'false') return false;
  return req.secure || req.headers['x-forwarded-proto'] === 'https';
}

function cookieOptions(req) {
  return { httpOnly: true, secure: isSecureRequest(req), sameSite: 'lax', path: '/' };
}

function getToken(req) {
  const auth = req.headers.authorization || '';
  if (auth.startsWith('Bearer ')) return auth.slice(7).trim();
  return req.cookies?.auth_token || '';
}

function buildAuth() {
  const disabled = process.env.AUTH_DISABLED === 'true';
  const secret = process.env.JWT_SECRET || '';
  const authServiceUrl = (process.env.AUTH_SERVICE_URL || 'http://auth-service:3100').replace(/\/$/, '');
  const sessionCache = new Map();

  async function checkCurrentSession(token, fallbackPayload) {
    const cached = sessionCache.get(token);
    if (cached && cached.expiresAt > Date.now()) return cached.user;
    if (cached) sessionCache.delete(token);
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 3000);
      const response = await fetch(`${authServiceUrl}/api/auth/session-status`, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${token}` },
        body: JSON.stringify({ app: APP_NAME }),
        signal: controller.signal,
      });
      clearTimeout(timer);
      if (response.status >= 500) {
        // A valid local JWT remains usable during a short AuthService outage.
        console.warn(`[auth] Session check unavailable: HTTP ${response.status}`);
        return fallbackPayload;
      }
      if (!response.ok) return null;
      const data = await response.json();
      if (sessionCache.size >= SESSION_CACHE_MAX_ENTRIES) {
        for (const [key, entry] of sessionCache) {
          if (entry.expiresAt <= Date.now()) sessionCache.delete(key);
        }
      }
      sessionCache.set(token, { user: data.user, expiresAt: Date.now() + 60_000 });
      return data.user;
    } catch (error) {
      // A valid local JWT remains usable during a short AuthService outage.
      console.warn(`[auth] Session check unavailable: ${error.message}`);
      return fallbackPayload;
    }
  }

  async function requireAuth(req, res, next) {
    if (disabled) {
      req.user = {
        sub: req.headers['x-dev-user'] || 'local-developer',
        username: 'developer',
        display_name: 'Local Explorer',
        is_admin: true,
        apps: [APP_NAME],
      };
      return next();
    }
    const token = getToken(req);
    if (!secret || !token) return res.status(401).json({ error: 'Not authenticated' });
    try {
      const payload = jwt.verify(token, secret);
      if (!payload.is_admin && !payload.apps?.includes(APP_NAME)) {
        return res.status(403).json({ error: 'No Roamline access' });
      }
      const current = await checkCurrentSession(token, payload);
      if (!current) return res.status(401).json({ error: 'Session expired or access revoked' });
      req.user = current;
      return next();
    } catch {
      return res.status(401).json({ error: 'Invalid or expired session' });
    }
  }

  async function login(req, res) {
    const { username, password, client } = req.body || {};
    if (!username || !password) return res.status(400).json({ error: 'Username and password are required' });
    try {
      const response = await fetch(`${authServiceUrl}/api/auth/login`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        body: JSON.stringify({ username, password, app: APP_NAME }),
      });
      const data = await response.json();
      if (!response.ok) return res.status(response.status).json(data);
      if (data.must_change_password) return res.json(data);
      res.cookie('auth_token', data.token, { ...cookieOptions(req), maxAge: SESSION_MAX_AGE_MS });
      const result = {
        username: data.username,
        display_name: data.display_name,
        is_admin: data.is_admin,
      };
      if (client === 'ios') result.token = data.token;
      return res.json(result);
    } catch (error) {
      console.error('[auth] Login failed:', error.message);
      return res.status(503).json({ error: 'Authentication service is unavailable' });
    }
  }

  function logout(req, res) {
    res.clearCookie('auth_token', cookieOptions(req));
    res.json({ ok: true });
  }

  return { requireAuth, login, logout, getToken };
}

module.exports = { APP_NAME, buildAuth };
