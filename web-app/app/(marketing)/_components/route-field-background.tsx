"use client";

import { useEffect, useRef } from "react";
import {
  createRouteFieldRenderer,
  ROUTE_FIELD_DEFAULTS,
  type RouteFieldOptions,
} from "./route-field-renderer";

export function RouteFieldBackground({
  className = "",
  mode = ROUTE_FIELD_DEFAULTS.mode,
  speed = ROUTE_FIELD_DEFAULTS.speed,
}: Partial<RouteFieldOptions> & { className?: string }) {
  const hostRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const optionsRef = useRef<RouteFieldOptions>({ mode, speed });

  useEffect(() => {
    optionsRef.current = { mode, speed };
  }, [mode, speed]);

  useEffect(() => {
    const host = hostRef.current;
    const canvas = canvasRef.current;
    if (!host || !canvas) return undefined;

    const renderer = createRouteFieldRenderer(canvas, () => optionsRef.current);
    if (!renderer) return undefined;

    let frame = 0;
    let visible = true;

    const resize = () => {
      const bounds = host.getBoundingClientRect();
      renderer.resize(bounds.width, bounds.height);
      renderer.render();
    };

    const tick = () => {
      renderer.render();
      frame = visible && !document.hidden ? requestAnimationFrame(tick) : 0;
    };

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(host);

    const intersectionObserver = new IntersectionObserver(([entry]) => {
      visible = entry?.isIntersecting ?? true;
      if (visible && !frame) frame = requestAnimationFrame(tick);
      if (!visible && frame) {
        cancelAnimationFrame(frame);
        frame = 0;
      }
    });
    intersectionObserver.observe(host);

    const handleVisibilityChange = () => {
      if (document.hidden && frame) {
        cancelAnimationFrame(frame);
        frame = 0;
      } else if (!document.hidden && visible && !frame) {
        frame = requestAnimationFrame(tick);
      }
    };
    document.addEventListener("visibilitychange", handleVisibilityChange);

    resize();
    frame = requestAnimationFrame(tick);

    return () => {
      resizeObserver.disconnect();
      intersectionObserver.disconnect();
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      if (frame) cancelAnimationFrame(frame);
    };
  }, []);

  return (
    <div
      ref={hostRef}
      aria-hidden="true"
      className={`pointer-events-none absolute inset-0 overflow-hidden ${className}`}
    >
      <canvas ref={canvasRef} className="h-full w-full" />
    </div>
  );
}
