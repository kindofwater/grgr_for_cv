import { useEffect, useRef } from "react";
import "./Toast.css";

// 우측 하단 비차단 안내. variant: 'info'(기본·파랑) | 'error'(빨강)
export default function Toast({ message, onClose, duration = 1500, variant = "info" }) {
  const onCloseRef = useRef(onClose);
  onCloseRef.current = onClose;

  useEffect(() => {
    const timerId = window.setTimeout(() => {
      onCloseRef.current?.();
    }, duration);

    return () => window.clearTimeout(timerId);
  }, [duration, message]);

  return (
    <div className="toast-region" aria-live="polite" aria-atomic="true">
      <div
        className={`toast-message toast-${variant}`}
        role="status"
        style={{ "--toast-duration": `${duration}ms` }}
      >
        {message}
      </div>
    </div>
  );
}
