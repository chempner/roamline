async function request(path, options = {}) {
  const response = await fetch(path, {
    credentials: 'include',
    ...options,
    headers: {
      ...(options.body && !(options.body instanceof FormData) ? { 'content-type': 'application/json' } : {}),
      ...(options.headers || {}),
    },
  });
  if (response.status === 204) return null;
  const data = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(data.error || `Request failed (${response.status})`);
  return data;
}

export const api = {
  me: () => request('/api/auth/me'),
  login: (username, password) => request('/api/auth/login', { method: 'POST', body: JSON.stringify({ username, password }) }),
  logout: () => request('/api/auth/logout', { method: 'POST' }),
  dashboard: () => request('/api/dashboard'),
  trip: (id) => request(`/api/trips/${id}`),
  createTrip: (trip) => request('/api/trips', { method: 'POST', body: JSON.stringify(trip) }),
  updateTrip: (id, trip) => request(`/api/trips/${id}`, { method: 'PATCH', body: JSON.stringify(trip) }),
  deleteTrip: (id) => request(`/api/trips/${id}`, { method: 'DELETE' }),
  createMoment: (tripId, moment) => request(`/api/trips/${tripId}/moments`, { method: 'POST', body: JSON.stringify(moment) }),
  updateMoment: (momentId, moment) => request(`/api/moments/${momentId}`, { method: 'PATCH', body: JSON.stringify(moment) }),
  uploadPhoto: (momentId, file, caption = '') => {
    const body = new FormData();
    body.append('photo', file);
    body.append('caption', caption);
    return request(`/api/moments/${momentId}/photos`, { method: 'POST', body });
  },
  shareTrip: (tripId, enabled) => request(`/api/trips/${tripId}/share`, { method: 'POST', body: JSON.stringify({ enabled }) }),
  publicTrip: (token) => request(`/api/public/trips/${token}`),
};
