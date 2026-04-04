import { useEffect, useRef, useState } from 'react';

/** Same host as the page (works with ngrok). Local dev (Vite on 5173) uses 8765. */
function getWsUrl(): string {
  const { protocol, hostname, port } = window.location;
  if (hostname === 'localhost' && port !== '8765') {
    return 'ws://localhost:8765/stream';
  }
  return (protocol === 'https:' ? 'wss:' : 'ws:') + '//' + window.location.host + '/stream';
}

type Status = 'connecting' | 'live' | 'disconnected';

export function VideoStream() {
  const [status, setStatus] = useState<Status>('connecting');
  const [imageUrl, setImageUrl] = useState<string | null>(null);
  const wsRef = useRef<WebSocket | null>(null);
  const prevUrlRef = useRef<string | null>(null);
  const cleanupRef = useRef(false);

  useEffect(() => {
    cleanupRef.current = false;
    const ws = new WebSocket(getWsUrl());
    ws.binaryType = 'arraybuffer';
    wsRef.current = ws;

    ws.onopen = () => {
      if (!cleanupRef.current) setStatus('live');
    };
    ws.onclose = () => {
      wsRef.current = null;
      if (!cleanupRef.current) setStatus('disconnected');
    };
    ws.onerror = () => {
      if (!cleanupRef.current) setStatus('disconnected');
    };

    ws.onmessage = (event) => {
      if (typeof event.data !== 'object' || !(event.data instanceof ArrayBuffer)) return;
      const bytes = new Uint8Array(event.data);
      if (bytes.length === 0) return;
      const blob = new Blob([bytes], { type: 'image/jpeg' });
      const url = URL.createObjectURL(blob);
      if (prevUrlRef.current) URL.revokeObjectURL(prevUrlRef.current);
      prevUrlRef.current = url;
      setImageUrl(url);
    };

    return () => {
      cleanupRef.current = true;
      if (ws.readyState === WebSocket.CONNECTING || ws.readyState === WebSocket.OPEN) {
        ws.close();
      }
      wsRef.current = null;
      if (prevUrlRef.current) {
        URL.revokeObjectURL(prevUrlRef.current);
        prevUrlRef.current = null;
      }
    };
  }, []);

  if (status === 'connecting') {
    return <p className="stream-status">Connecting…</p>;
  }
  if (status === 'disconnected') {
    return <p className="stream-status">Disconnected</p>;
  }
  return (
    <div className="stream-container">
      {imageUrl && (
        <img src={imageUrl} alt="Live stream" className="stream-video" />
      )}
    </div>
  );
}
