import { useEffect, useRef } from 'react';
import L from 'leaflet';
import 'leaflet/dist/leaflet.css';

const fallbackCenter = [46.8, 8.2];

export function MapView({ route = [], moments = [], interactive = true, className = '' }) {
  const nodeRef = useRef(null);
  const mapRef = useRef(null);
  const layerRef = useRef(null);

  useEffect(() => {
    if (!nodeRef.current || mapRef.current) return undefined;
    const map = L.map(nodeRef.current, {
      zoomControl: false,
      attributionControl: false,
      scrollWheelZoom: interactive,
      dragging: interactive,
    }).setView(fallbackCenter, 7);
    L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
      maxZoom: 19,
      attribution: '&copy; OpenStreetMap contributors',
    }).addTo(map);
    L.control.zoom({ position: 'bottomright' }).addTo(map);
    L.control.attribution({ position: 'bottomleft', prefix: false }).addTo(map);
    layerRef.current = L.featureGroup().addTo(map);
    mapRef.current = map;
    const observer = new ResizeObserver(() => map.invalidateSize());
    observer.observe(nodeRef.current);
    return () => {
      observer.disconnect();
      map.remove();
      mapRef.current = null;
    };
  }, [interactive]);

  useEffect(() => {
    const map = mapRef.current;
    const layer = layerRef.current;
    if (!map || !layer) return;
    layer.clearLayers();

    const coordinates = route.map((point) => [point.latitude, point.longitude]);
    if (coordinates.length > 1) {
      L.polyline(coordinates, { color: '#fff', weight: 9, opacity: 0.34, lineCap: 'round' }).addTo(layer);
      L.polyline(coordinates, { color: '#e66546', weight: 5, opacity: 0.92, lineCap: 'round', lineJoin: 'round' }).addTo(layer);
    } else if (coordinates.length === 1) {
      L.circleMarker(coordinates[0], { radius: 7, fillColor: '#e66546', fillOpacity: 1, color: '#fff', weight: 3 }).addTo(layer);
    }

    moments.filter((moment) => moment.latitude != null && moment.longitude != null).forEach((moment) => {
      const icon = L.divIcon({
        className: 'moment-map-icon',
        html: `<span>${moment.number}</span>`,
        iconSize: [34, 34],
        iconAnchor: [17, 17],
      });
      const label = document.createElement('span');
      label.textContent = moment.title;
      L.marker([moment.latitude, moment.longitude], { icon })
        .bindTooltip(label, { direction: 'top', offset: [0, -14] })
        .addTo(layer);
    });

    if (layer.getLayers().length) map.fitBounds(layer.getBounds().pad(0.18), { maxZoom: 13, animate: false });
    else map.setView(fallbackCenter, 7);
  }, [route, moments]);

  return <div ref={nodeRef} className={`map ${className}`} aria-label="Trip route map" />;
}
