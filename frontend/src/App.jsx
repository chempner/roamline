import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  ArrowRight, CalendarDays, Check, ChevronRight, CircleStop, Compass, Download,
  Footprints, Globe2, LoaderCircle, LogOut, Map, MapPin, Menu, Navigation,
  Plus, Route, Share2, Sparkles, X,
} from 'lucide-react';
import { api } from './api';
import { MapView } from './components/MapView';

const dateFormatter = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', year: 'numeric' });
const shortDate = new Intl.DateTimeFormat(undefined, { day: 'numeric', month: 'short', timeZone: 'UTC' });

function formatDate(value, short = false) {
  if (!value) return 'Open date';
  return (short ? shortDate : dateFormatter).format(new Date(value));
}

function tripDates(trip) {
  if (!trip.start_date) return 'Dates not set';
  return `${formatDate(trip.start_date, true)}${trip.end_date ? ` – ${formatDate(trip.end_date, true)}` : ''}`;
}

function EmptyMapDecoration() {
  return (
    <div className="empty-map-decoration" aria-hidden="true">
      <div className="route-line"><span /><span /><span /></div>
      <Globe2 size={64} strokeWidth={1.25} />
    </div>
  );
}

function Login({ onLogin }) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  async function submit(event) {
    event.preventDefault();
    setLoading(true);
    setError('');
    try { await onLogin(username, password); }
    catch (err) { setError(err.message); }
    finally { setLoading(false); }
  }

  return (
    <main className="login-page">
      <section className="login-story">
        <div className="brand brand-light"><span className="brand-mark"><Route size={20} /></span>Roamline</div>
        <div className="login-copy">
          <span className="eyebrow light">YOUR JOURNEY, YOUR DATA</span>
          <h1>Keep the road.<br />Tell the story.</h1>
          <p>Automatically trace where you go, pin the moments that matter, and keep every adventure on your own server.</p>
          <div className="login-features">
            <span><Navigation size={17} /> Background GPS tracking</span>
            <span><MapPin size={17} /> A living travel journal</span>
            <span><Globe2 size={17} /> Private, shareable maps</span>
          </div>
        </div>
        <div className="login-orbit" aria-hidden="true"><span /><span /><span /><Compass /></div>
      </section>
      <section className="login-panel">
        <form className="login-card" onSubmit={submit}>
          <span className="eyebrow">WELCOME BACK</span>
          <h2>Continue exploring</h2>
          <p className="muted">Sign in with your AuthService account.</p>
          <label>Username<input autoCapitalize="none" autoComplete="username" value={username} onChange={(e) => setUsername(e.target.value)} required /></label>
          <label>Password<input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required /></label>
          {error && <div className="form-error">{error}</div>}
          <button className="button primary wide" disabled={loading}>
            {loading ? <LoaderCircle className="spin" size={18} /> : <>Sign in <ArrowRight size={18} /></>}
          </button>
          <p className="login-note">Accounts and access are managed centrally in AuthService.</p>
        </form>
      </section>
    </main>
  );
}

function Modal({ title, subtitle, onClose, children }) {
  return (
    <div className="modal-backdrop" onMouseDown={onClose}>
      <section className="modal" onMouseDown={(event) => event.stopPropagation()}>
        <div className="modal-heading"><div><h2>{title}</h2>{subtitle && <p>{subtitle}</p>}</div><button className="icon-button" onClick={onClose} aria-label="Close"><X /></button></div>
        {children}
      </section>
    </div>
  );
}

function TripForm({ onClose, onSave }) {
  const today = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);
  const [form, setForm] = useState({ title: '', summary: '', start_date: today, end_date: '', status: 'planned' });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const update = (key) => (event) => setForm((value) => ({ ...value, [key]: event.target.value }));
  async function submit(event) {
    event.preventDefault();
    setSaving(true);
    try { await onSave(form); onClose(); } catch (err) { setError(err.message); setSaving(false); }
  }
  return (
    <Modal title="Plan a new journey" subtitle="Give the adventure a name. You can change everything later." onClose={onClose}>
      <form className="stack-form" onSubmit={submit}>
        <label>Trip name<input value={form.title} onChange={update('title')} placeholder="Summer through the Alps" autoFocus required /></label>
        <label>Short description<textarea value={form.summary} onChange={update('summary')} placeholder="What are you looking forward to?" rows="3" /></label>
        <div className="form-grid"><label>Starts<input type="date" value={form.start_date} onChange={update('start_date')} /></label><label>Ends<input type="date" value={form.end_date} onChange={update('end_date')} /></label></div>
        <label>Stage<select value={form.status} onChange={update('status')}><option value="planned">Planning</option><option value="active">On the road</option><option value="completed">Completed</option></select></label>
        {error && <div className="form-error">{error}</div>}
        <div className="modal-actions"><button type="button" className="button ghost" onClick={onClose}>Cancel</button><button className="button primary" disabled={saving}>{saving ? <LoaderCircle className="spin" size={18} /> : <><Sparkles size={17} /> Create trip</>}</button></div>
      </form>
    </Modal>
  );
}

function MomentForm({ trip, onClose, onSave }) {
  const now = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 16);
  const lastPoint = trip.route?.at(-1);
  const [form, setForm] = useState({ title: '', story: '', place: '', visited_at: now, latitude: lastPoint?.latitude ?? null, longitude: lastPoint?.longitude ?? null });
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [photo, setPhoto] = useState(null);
  const createdRef = useRef(null);
  const uploadedRef = useRef(false);
  const update = (key) => (event) => setForm((value) => ({ ...value, [key]: event.target.value }));
  async function submit(event) {
    event.preventDefault(); setSaving(true);
    try { await onSave({ ...form, visited_at: new Date(form.visited_at).toISOString(), latitude: form.latitude ?? undefined, longitude: form.longitude ?? undefined }, photo, createdRef, uploadedRef); onClose(); }
    catch (err) { setError(err.message); setSaving(false); }
  }
  return (
    <Modal title="Add a moment" subtitle={`Capture a stop on ${trip.title}.`} onClose={onClose}>
      <form className="stack-form" onSubmit={submit}>
        <label>Moment title<input value={form.title} onChange={update('title')} placeholder="Sunrise above the valley" autoFocus required /></label>
        <label>Place<input value={form.place} onChange={update('place')} placeholder="Grindelwald, Switzerland" /></label>
        <label>Your story<textarea value={form.story} onChange={update('story')} placeholder="What happened here?" rows="5" /></label>
        <label>Photo<input className="file-input" type="file" accept="image/jpeg,image/png,image/webp,image/heic,image/heif" onChange={(event) => setPhoto(event.target.files?.[0] || null)} /></label>
        <label>Date and time<input type="datetime-local" value={form.visited_at} onChange={update('visited_at')} required /></label>
        {error && <div className="form-error">{error}</div>}
        <div className="modal-actions"><button type="button" className="button ghost" onClick={onClose}>Cancel</button><button className="button primary" disabled={saving}><MapPin size={17} /> Save moment</button></div>
      </form>
    </Modal>
  );
}

function StatusBadge({ status }) {
  const labels = { planned: 'Planning', active: 'On the road', completed: 'Completed' };
  return <span className={`status status-${status}`}><span />{labels[status]}</span>;
}

function TripSidebar({ trips, selectedId, onSelect, onCreate, open, onClose }) {
  return (
    <aside className={`sidebar ${open ? 'sidebar-open' : ''}`}>
      <div className="sidebar-mobile-heading"><span>Journeys</span><button className="icon-button" onClick={onClose}><X /></button></div>
      <button className="new-trip-card" onClick={onCreate}><span><Plus size={20} /></span><div><strong>New journey</strong><small>Start planning</small></div></button>
      <div className="sidebar-label">YOUR JOURNEYS <span>{trips.length}</span></div>
      <div className="trip-list">
        {trips.map((trip) => (
          <button key={trip.id} className={`trip-list-item ${trip.id === selectedId ? 'active' : ''}`} onClick={() => { onSelect(trip.id); onClose(); }}>
            <div className="trip-list-icon"><Map size={19} /></div>
            <div className="trip-list-copy"><strong>{trip.title}</strong><small>{tripDates(trip)}</small><span>{trip.distance_km} km · {trip.moment_count} moments</span></div>
            <ChevronRight size={17} />
          </button>
        ))}
      </div>
      <div className="ios-callout"><div className="phone-dot"><Navigation size={18} /></div><div><strong>Track from your pocket</strong><p>Use the Roamline iOS app for automatic background GPS.</p></div></div>
    </aside>
  );
}

function EmptyState({ onCreate }) {
  return (
    <div className="empty-state">
      <div className="empty-visual"><EmptyMapDecoration /></div>
      <span className="eyebrow">THE MAP IS WAITING</span>
      <h1>Where will you go next?</h1>
      <p>Create a journey, then let the iOS app trace your route while you collect the moments along the way.</p>
      <button className="button primary" onClick={onCreate}><Plus size={18} /> Plan your first trip</button>
    </div>
  );
}

function TripView({ trip, onMoment, onStatus, onShare, busy }) {
  const [copied, setCopied] = useState(false);
  const moments = useMemo(() => (trip.moments || []).map((moment, index, list) => ({ ...moment, number: list.length - index })), [trip.moments]);
  async function copyLink(token) {
    await navigator.clipboard?.writeText(`${window.location.origin}/shared/${token}`);
    setCopied(true);
    setTimeout(() => setCopied(false), 1800);
  }
  async function share() {
    if (trip.share_token) return copyLink(trip.share_token);
    const result = await onShare(true);
    if (result?.share_token) await copyLink(result.share_token);
  }
  return (
    <div className="trip-view">
      <section className="map-hero">
        <MapView route={trip.route} moments={moments} />
        {!trip.route?.length && <div className="map-empty-note"><Navigation size={19} /><span>Start tracking on iPhone to draw your route</span></div>}
        <div className="map-top-actions">
          <button className={`map-action ${trip.share_token ? 'active' : ''}`} onClick={share}><Share2 size={17} /> {copied ? 'Link copied' : trip.share_token ? 'Copy link' : 'Share'}</button>
          {trip.share_token && <button className="map-action" title="Stop sharing" onClick={() => onShare(false)}><X size={17} /> Stop sharing</button>}
          <a className="map-action" href={`/api/trips/${trip.id}/export.geojson`}><Download size={17} /> GeoJSON</a>
        </div>
        <div className="trip-hero-card">
          <StatusBadge status={trip.status} />
          <h1>{trip.title}</h1>
          <p>{trip.summary || 'Your route and stories will collect here as the journey unfolds.'}</p>
          <div className="hero-meta"><span><CalendarDays size={16} />{tripDates(trip)}</span><span><Route size={16} />{trip.distance_km} km</span><span><MapPin size={16} />{trip.moment_count} moments</span></div>
        </div>
      </section>
      <section className="journal-section">
        <div className="journal-heading">
          <div><span className="eyebrow">TRAVEL JOURNAL</span><h2>The story so far</h2></div>
          <div className="journal-actions">
            {trip.status !== 'active' && <button className="button outline" disabled={busy} onClick={() => onStatus('active')}><Navigation size={17} /> Start tracking</button>}
            {trip.status === 'active' && <button className="button outline" disabled={busy} onClick={() => onStatus('completed')}><CircleStop size={17} /> Finish trip</button>}
            <button className="button primary" onClick={onMoment}><Plus size={17} /> Add moment</button>
          </div>
        </div>
        {moments.length ? (
          <div className="timeline">
            {moments.map((moment) => (
              <article className="moment-card" key={moment.id}>
                <div className="timeline-marker"><span>{moment.number}</span></div>
                <div className="moment-date">{formatDate(moment.visited_at)}<span>{moment.place || 'Somewhere wonderful'}</span></div>
                <div className="moment-content">
                  <div className="moment-icon"><MapPin /></div>
                  <div className="moment-copy"><h3>{moment.title}</h3>{moment.story && <p>{moment.story}</p>}
                    {!!moment.photos?.length && <div className="moment-photos">{moment.photos.map((photo) => <img key={photo.id} src={photo.url} alt={photo.caption || moment.title} loading="lazy" />)}</div>}
                    <small>{moment.photo_count ? `${moment.photo_count} photo${moment.photo_count === 1 ? '' : 's'}` : 'No photos yet'}</small>
                  </div>
                </div>
              </article>
            ))}
          </div>
        ) : (
          <div className="journal-empty"><div><Footprints /></div><h3>Your first moment starts the story</h3><p>Pin a place, write a note, and watch your travel journal take shape.</p><button className="text-button" onClick={onMoment}>Add the first moment <ArrowRight size={16} /></button></div>
        )}
      </section>
    </div>
  );
}

function PublicTrip({ token }) {
  const [state, setState] = useState({ loading: true, trip: null, error: '' });
  useEffect(() => { api.publicTrip(token).then(({ trip }) => setState({ loading: false, trip, error: '' })).catch((error) => setState({ loading: false, trip: null, error: error.message })); }, [token]);
  if (state.loading) return <div className="center-loader"><LoaderCircle className="spin" /></div>;
  if (!state.trip) return <div className="public-error"><Route size={42} /><h1>Journey not found</h1><p>{state.error}</p></div>;
  const trip = state.trip;
  return (
    <main className="public-page"><header className="public-header"><div className="brand"><span className="brand-mark"><Route size={20} /></span>Roamline</div><span>A shared journey</span></header><TripView trip={trip} onMoment={() => {}} onStatus={() => {}} onShare={() => {}} busy /></main>
  );
}

export default function App() {
  const sharedToken = useMemo(() => window.location.pathname.match(/^\/shared\/([^/]+)/)?.[1], []);
  const [session, setSession] = useState({ loading: !sharedToken, user: null });
  const [data, setData] = useState({ trips: [], totals: null });
  const [selectedId, setSelectedId] = useState(null);
  const [trip, setTrip] = useState(null);
  const [tripError, setTripError] = useState('');
  const [tripRetry, setTripRetry] = useState(0);
  const selectedIdRef = useRef(null);
  selectedIdRef.current = selectedId;
  const [modal, setModal] = useState(null);
  const [sidebarOpen, setSidebarOpen] = useState(false);
  const [busy, setBusy] = useState(false);

  const loadDashboard = useCallback(async (preferredId) => {
    const dashboard = await api.dashboard();
    setData(dashboard);
    setSelectedId((current) => preferredId || current || dashboard.trips[0]?.id || null);
  }, []);

  useEffect(() => {
    if (sharedToken) return;
    api.me().then(({ user }) => { setSession({ loading: false, user }); loadDashboard().catch((error) => console.error('Failed to load dashboard', error)); })
      .catch(() => setSession({ loading: false, user: null }));
  }, [loadDashboard, sharedToken]);

  useEffect(() => {
    if (!selectedId || !session.user) { setTrip(null); return; }
    let active = true;
    setTripError('');
    api.trip(selectedId).then(({ trip: value }) => { if (active) setTrip(value); }).catch((error) => { if (active) { setTrip(null); setTripError(error.message); } });
    return () => { active = false; };
  }, [selectedId, session.user, tripRetry]);

  if (sharedToken) return <PublicTrip token={sharedToken} />;
  if (session.loading) return <div className="center-loader"><LoaderCircle className="spin" /></div>;
  if (!session.user) return <Login onLogin={async (username, password) => { const result = await api.login(username, password); if (result?.must_change_password) throw new Error('You must change your password before signing in. Please update it in AuthService first.'); const { user } = await api.me(); setSession({ loading: false, user }); await loadDashboard(); }} />;

  async function refreshTrip() {
    if (!selectedId) return;
    const result = await api.trip(selectedId);
    if (selectedIdRef.current !== selectedId) return;
    setTrip(result.trip); await loadDashboard(selectedId);
  }

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="header-left"><button className="mobile-menu icon-button" onClick={() => setSidebarOpen(true)}><Menu /></button><div className="brand"><span className="brand-mark"><Route size={20} /></span>Roamline</div></div>
        <div className="header-stats"><span><strong>{data.totals?.trips || 0}</strong> journeys</span><span><strong>{data.totals?.distance_km || 0}</strong> km traced</span><span><strong>{data.totals?.moments || 0}</strong> moments</span></div>
        <div className="user-menu"><div className="avatar">{(session.user.display_name || session.user.username || 'R').slice(0, 1).toUpperCase()}</div><div><strong>{session.user.display_name || session.user.username}</strong><small>Explorer</small></div><button className="icon-button" title="Sign out" onClick={async () => { await api.logout(); setSession({ loading: false, user: null }); }}><LogOut size={18} /></button></div>
      </header>
      <div className="app-body">
        <TripSidebar trips={data.trips} selectedId={selectedId} onSelect={setSelectedId} onCreate={() => setModal('trip')} open={sidebarOpen} onClose={() => setSidebarOpen(false)} />
        <main className="main-content">
          {!data.trips.length ? <EmptyState onCreate={() => setModal('trip')} /> : tripError ? (
            <div className="trip-error"><Route size={42} /><h3>Could not load this trip</h3><p>{tripError}</p><button className="button outline" onClick={() => setTripRetry((count) => count + 1)}>Try again</button></div>
          ) : !trip ? <div className="center-loader"><LoaderCircle className="spin" /></div> : (
            <TripView
              key={trip.id}
              trip={trip}
              busy={busy}
              onMoment={() => setModal('moment')}
              onStatus={async (status) => { setBusy(true); try { await api.updateTrip(trip.id, { status }); await refreshTrip(); } finally { setBusy(false); } }}
              onShare={async (enabled) => { const result = await api.shareTrip(trip.id, enabled); await refreshTrip(); return result; }}
            />
          )}
        </main>
      </div>
      {modal === 'trip' && <TripForm onClose={() => setModal(null)} onSave={async (value) => { const result = await api.createTrip(value); await loadDashboard(result.trip.id); }} />}
      {modal === 'moment' && trip && <MomentForm trip={trip} onClose={() => setModal(null)} onSave={async (value, photo, created, uploaded) => {
        if (!created.current) created.current = (await api.createMoment(trip.id, value)).moment.id;
        else await api.updateMoment(created.current, value);
        try { if (photo && !uploaded.current) { await api.uploadPhoto(created.current, photo); uploaded.current = true; } }
        catch (error) { await refreshTrip().catch((refreshError) => console.error('Failed to refresh trip after saving moment', refreshError)); throw new Error(`Moment saved, but the photo failed to upload: ${error.message}`); }
        await refreshTrip().catch((error) => console.error('Failed to refresh trip after saving moment', error));
      }} />}
      {sidebarOpen && <div className="sidebar-scrim" onClick={() => setSidebarOpen(false)} />}
    </div>
  );
}
