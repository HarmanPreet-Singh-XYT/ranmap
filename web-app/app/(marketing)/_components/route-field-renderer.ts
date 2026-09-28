/**
 * A handful of curved travel routes, each carrying a few glowing dots that
 * drift along it — a convoy visual metaphor for the hero background.
 * Self-contained canvas 2D renderer (no WebGL, no external assets),
 * following the pattern of ThreeUI's lightweight canvas effects
 * (predictive-arc / data-pixel-arc) but built for Ranmap's brand palette
 * and an actual "routes converging" shape rather than a single fixed arc.
 */

export type RouteFieldMode = "dark" | "light";

export type RouteFieldOptions = {
  mode: RouteFieldMode;
  speed: number;
};

export const ROUTE_FIELD_DEFAULTS: RouteFieldOptions = {
  mode: "light",
  speed: 1,
};

type Route = {
  // Control points as fractions of width/height, so the shape scales with
  // the canvas instead of being pixel-locked.
  from: [number, number];
  control: [number, number];
  to: [number, number];
  dotCount: number;
};

const ROUTES: Route[] = [
  { from: [-0.05, 0.75], control: [0.35, 0.15], to: [1.05, 0.55], dotCount: 5 },
  { from: [-0.05, 0.35], control: [0.4, 0.85], to: [1.05, 0.2], dotCount: 4 },
  { from: [0.1, -0.05], control: [0.6, 0.5], to: [0.85, 1.05], dotCount: 4 },
];

function quadPoint(
  t: number,
  from: [number, number],
  control: [number, number],
  to: [number, number],
): [number, number] {
  const mt = 1 - t;
  const x = mt * mt * from[0] + 2 * mt * t * control[0] + t * t * to[0];
  const y = mt * mt * from[1] + 2 * mt * t * control[1] + t * t * to[1];
  return [x, y];
}

export function createRouteFieldRenderer(
  canvas: HTMLCanvasElement,
  getOptions: () => RouteFieldOptions,
) {
  const context = canvas.getContext("2d", { alpha: true });
  if (!context) return null;

  let width = 1;
  let height = 1;
  let time = 0;

  const resize = (nextWidth: number, nextHeight: number) => {
    width = Math.max(1, nextWidth);
    height = Math.max(1, nextHeight);
    const pixelRatio = Math.min(window.devicePixelRatio || 1, 2);
    canvas.width = Math.round(width * pixelRatio);
    canvas.height = Math.round(height * pixelRatio);
    context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
  };

  const render = () => {
    const options = getOptions();
    const isLight = options.mode === "light";
    context.clearRect(0, 0, width, height);
    time += 0.006 * options.speed;

    // Neutral ink, not brand green — this is a restrained texture, not a
    // colored accent.
    const lineColor = isLight ? "rgba(10, 10, 10, 0.08)" : "rgba(250, 250, 250, 0.1)";

    for (const route of ROUTES) {
      const from: [number, number] = [route.from[0] * width, route.from[1] * height];
      const control: [number, number] = [route.control[0] * width, route.control[1] * height];
      const to: [number, number] = [route.to[0] * width, route.to[1] * height];

      // The faint route line itself.
      context.beginPath();
      context.moveTo(from[0], from[1]);
      context.quadraticCurveTo(control[0], control[1], to[0], to[1]);
      context.strokeStyle = lineColor;
      context.lineWidth = 1.5;
      context.stroke();

      // Dots traveling along the curve, evenly spaced and looping.
      for (let i = 0; i < route.dotCount; i++) {
        const offset = i / route.dotCount;
        const t = (time * 0.15 + offset) % 1;
        const [x, y] = quadPoint(t, from, control, to);

        // Fade in/out at the ends so dots don't pop at t=0/1.
        const edgeFade = Math.min(1, Math.min(t, 1 - t) * 8);
        const alpha = (isLight ? 0.4 : 0.5) * edgeFade;
        const lightness = isLight ? 10 : 96;

        const gradient = context.createRadialGradient(x, y, 0, x, y, 6);
        gradient.addColorStop(0, `hsla(0, 0%, ${lightness}%, ${alpha})`);
        gradient.addColorStop(1, `hsla(0, 0%, ${lightness}%, 0)`);
        context.fillStyle = gradient;
        context.beginPath();
        context.arc(x, y, 6, 0, Math.PI * 2);
        context.fill();
      }
    }
  };

  return { resize, render };
}
