import React from "react";
import { Video } from "@remotion/media";
import { AbsoluteFill, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Fin } from "../scenes/Fin";
import durees from "./voix-durees.json";
import { Audio } from "@remotion/media";

// The film of the beta (design/video-beta.md), slow enough to read every screen.
//
// A hand holds the iPhone and its thumb does what the person did in the real takes (public/
// prises/beta, the app in filming mode): it scrolls Today, a notification of Yumi comes, the
// thumb opens it, the app wakes; then one thing per shot, the thumb touching exactly when the
// app reacts. Last, the iPhone and the Mac side by side: a stream goes from one to the other
// and both celebrate. The camera barely moves: a slow push toward what matters, never a swing.
//
// Two formats (vertical 9:16, computer 16:9) and two openings (`reel`: the person's own
// first seconds, prises/beta/plan-reel.mp4, once `filmed`).

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ramp = (t: number, a: number, b: number, ease = EASE.camera) => interpolate(t, [a, b], [0, 1], { ...CLAMP, easing: ease });

/** The takes are an iPhone 16: 393 × 852 points. */
const PT = { w: 393, h: 852 };

type Touch = { readonly at: number; readonly x: number; readonly y: number; readonly to?: { x: number; y: number }; readonly hold?: number };
type Shot = {
  readonly take: string;
  readonly source: number;
  readonly length: number;
  readonly lines: readonly string[];
  readonly touches?: readonly Touch[];
  /** A slow push toward a point of the screen (in points), from `at`. */
  readonly push?: { readonly at: number; readonly x: number; readonly y: number; readonly zoom: number };
};

const RAW_SHOTS: readonly Shot[] = [
  {
    take: "defilement",
    source: 9.5,
    length: 9,
    lines: ["Tu fais défiler ta journée…"],
    touches: [
      { at: 3.3, x: 210, y: 650, to: { x: 210, y: 360 }, hold: 1.2 },
      { at: 5.9, x: 210, y: 330, to: { x: 210, y: 610 }, hold: 1.2 },
      // The notification
      { at: 8.1, x: 200, y: 92 },
    ],
  },
  { take: "lancement", source: 0.6, length: 8, lines: ["Yumi se réveille.", "Il a quelque chose pour toi."] },
  {
    take: "agents",
    source: 6.6,
    length: 8,
    lines: ["Claude Code veut pousser sur GitHub.", "Tu décides, d'un toucher."],
    touches: [{ at: 3.15, x: 308, y: 592 }],
    push: { at: 1.0, x: 200, y: 560, zoom: 1.22 },
  },
  {
    take: "parler",
    source: 7.0,
    length: 8,
    lines: ["Tu lui parles.", "Il réfléchit avec ton Claude Code."],
    push: { at: 1.2, x: 200, y: 640, zoom: 1.15 },
  },
  {
    take: "aujourdhui",
    source: 7.5,
    length: 8,
    lines: ["Ta journée, rangée comme tu veux."],
    touches: [
      { at: 1.4, x: 330, y: 84 },
      { at: 4.4, x: 340, y: 84 },
    ],
  },
  {
    take: "meteo",
    source: 8.0,
    length: 8.5,
    lines: ["Et il vit au rythme", "de ton ciel."],
    touches: [
      { at: 0.95, x: 47, y: 671 },
      { at: 2.95, x: 187, y: 671 },
      { at: 5.45, x: 254, y: 671 },
      { at: 7.45, x: 115, y: 671 },
    ],
  },
];

/** Each shot lasts at least its sentence of the voice. */
const SHOTS: readonly Shot[] = RAW_SHOTS.map((s, i) => ({ ...s, length: Math.max(s.length, (durees.iphone[i] ?? 0) + 1.0) }));
const LINK = Math.max(11, (durees.iphone[RAW_SHOTS.length] ?? 0) + 1.5);
const END = Math.max(3.3, (durees.iphone[RAW_SHOTS.length + 1] ?? 0) + 0.6);
const shotsLength = SHOTS.reduce((sum, s) => sum + s.length, 0);
export const BETA_LENGTH = shotsLength + LINK + END;

const Take: React.FC<{ readonly name: string; readonly source: number }> = ({ name, source }) => {
  const { fps } = useVideoConfig();
  return (
    <Video
      src={staticFile(`prises/beta/${name}.mp4`)}
      muted
      trimBefore={Math.round(source * fps)}
      style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }}
    />
  );
};

/** The iPhone as an object: a titanium edge, the black glass and one soft reflection. */
const Phone: React.FC<{ readonly width: number; readonly children: React.ReactNode }> = ({ width, children }) => {
  const bezel = width * 0.028;
  const height = width * (PT.h / PT.w);
  return (
    <div style={{ position: "relative", width: width + bezel * 2, height: height + bezel * 2 }}>
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: width * 0.165,
          background: "linear-gradient(140deg, #55565c 0%, #1d1e22 28%, #0d0d10 62%, #3c3d42 100%)",
          boxShadow: "inset 0 0 0 2px rgba(255,255,255,0.08), 0 50px 140px rgba(0,0,0,0.7)",
        }}
      />
      <div style={{ position: "absolute", left: bezel, top: bezel, width, height, borderRadius: width * 0.14, overflow: "hidden", background: "#000" }}>
        {children}
        <div style={{ position: "absolute", inset: 0, background: "linear-gradient(118deg, transparent 38%, rgba(255,255,255,0.06) 50%, transparent 62%)" }} />
      </div>
    </div>
  );
};

/** The hand holding it: fingers behind on the left, the palm under it, the thumb in front. */
const SKIN = { light: "#d9a98c", mid: "#c08a6c", dark: "#8f6049" };

const Grip: React.FC<{ readonly width: number; readonly side: "behind" | "front"; readonly thumb: { x: number; y: number; press: number } }> = ({
  width,
  side,
  thumb,
}) => {
  const height = width * (PT.h / PT.w);
  const bezel = width * 0.028;
  const W = width + bezel * 2;
  const H = height + bezel * 2;
  if (side === "behind") {
    return (
      <svg width={W * 2} height={H * 1.5} viewBox={`0 0 ${W * 2} ${H * 1.5}`} style={{ position: "absolute", left: -W * 0.5, top: 0, overflow: "visible", pointerEvents: "none" }}>
        <defs>
          <linearGradient id="skin" x1="0" y1="0" x2="1" y2="1">
            <stop offset="0" stopColor={SKIN.light} />
            <stop offset="1" stopColor={SKIN.dark} />
          </linearGradient>
        </defs>
        {/* Palm and wrist, under the phone, leaving the frame at the bottom */}
        <path
          d={`M ${W * 0.55} ${H * 0.62} C ${W * 0.45} ${H * 0.95}, ${W * 0.6} ${H * 1.5}, ${W * 0.9} ${H * 1.5} L ${W * 1.75} ${H * 1.5} C ${W * 1.7} ${H * 1.2}, ${W * 1.6} ${H * 0.95}, ${W * 1.52} ${H * 0.72} Z`}
          fill="url(#skin)"
        />
        {/* Three fingers wrapped on the left edge */}
        {[0.5, 0.63, 0.76].map((y, i) => (
          <rect key={y} x={W * 0.39} y={H * y} width={W * 0.18} height={H * 0.1} rx={H * 0.05} fill="url(#skin)" opacity={1 - i * 0.05} />
        ))}
      </svg>
    );
  }
  // The thumb: from the right of the palm to its tip, which presses where the take was touched
  const baseX = W * 1.02;
  const baseY = H * 0.95;
  const tipX = bezel + thumb.x;
  const tipY = bezel + thumb.y;
  const angle = Math.atan2(tipY - baseY, tipX - baseX);
  const length = Math.hypot(tipX - baseX, tipY - baseY) + W * 0.05;
  const thickness = W * 0.17 * (1 - 0.06 * thumb.press);
  return (
    <div style={{ position: "absolute", left: 0, top: 0, width: W, height: H, pointerEvents: "none" }}>
      {/* The press, on the glass */}
      <div
        style={{
          position: "absolute",
          left: tipX - W * 0.07,
          top: tipY - W * 0.07,
          width: W * 0.14,
          height: W * 0.14,
          borderRadius: "50%",
          background: "rgba(255,255,255,0.32)",
          transform: `scale(${0.5 + thumb.press})`,
          opacity: thumb.press * 0.9,
        }}
      />
      <div
        style={{
          position: "absolute",
          left: baseX,
          top: baseY - thickness / 2,
          width: length,
          height: thickness,
          borderRadius: thickness / 2,
          background: `linear-gradient(180deg, ${SKIN.light}, ${SKIN.mid} 60%, ${SKIN.dark})`,
          transformOrigin: "0 50%",
          transform: `rotate(${angle}rad)`,
          boxShadow: `0 ${18 - 10 * thumb.press}px ${40 - 20 * thumb.press}px rgba(0,0,0,0.45)`,
        }}
      >
        {/* The nail */}
        <div style={{ position: "absolute", right: thickness * 0.12, top: thickness * 0.2, width: thickness * 0.55, height: thickness * 0.6, borderRadius: thickness * 0.3, background: "rgba(255,235,225,0.55)" }} />
      </div>
    </div>
  );
};

/** Where the thumb is at `t` in a shot: resting on the side, or going to touch, sliding, leaving. */
const thumbAt = (touches: readonly Touch[] | undefined, t: number, width: number) => {
  const scale = width / PT.w;
  const rest = { x: PT.w * 0.98 * scale, y: PT.h * 0.82 * scale, press: 0 };
  if (!touches) return rest;
  for (const touch of touches) {
    const go = touch.at - 0.6;
    const hold = touch.hold ?? 0.25;
    const back = touch.at + hold + 0.6;
    if (t < go || t > back) continue;
    const reach = ramp(t, go, touch.at, EASE.out);
    const leave = ramp(t, touch.at + hold, back, EASE.in);
    const slide = touch.to ? ramp(t, touch.at, touch.at + hold, EASE.camera) : 0;
    const x = (touch.x + (touch.to ? (touch.to.x - touch.x) * slide : 0)) * scale;
    const y = (touch.y + (touch.to ? (touch.to.y - touch.y) * slide : 0)) * scale;
    const press = t >= touch.at && t <= touch.at + hold ? 1 : 0;
    const k = reach * (1 - leave);
    return { x: rest.x + (x - rest.x) * k, y: rest.y + (y - rest.y) * k, press: press * k };
  }
  return rest;
};

/** A notification of Yumi, as iOS draws it, inside the screen. */
const Banner: React.FC<{ readonly t: number; readonly at: number; readonly scale: number }> = ({ t, at, scale }) => {
  const { fps } = useVideoConfig();
  const p = spring({ frame: Math.max(0, (t - at) * fps), fps, config: { damping: 18, stiffness: 120 } });
  const s = scale;
  return (
    <div
      style={{
        position: "absolute",
        left: 10 * s,
        right: 10 * s,
        top: 52 * s,
        padding: `${11 * s}px ${12 * s}px`,
        borderRadius: 22 * s,
        background: "rgba(44,44,50,0.86)",
        backdropFilter: "blur(20px)",
        display: "flex",
        gap: 10 * s,
        alignItems: "center",
        transform: `translateY(${(1 - p) * -120 * s}px)`,
        opacity: Math.min(1, p * 1.5),
        fontFamily: THEME.text,
        color: THEME.fg,
      }}
    >
      <Img src={staticFile("prises/beta/icone.png")} style={{ width: 38 * s, height: 38 * s, borderRadius: 9 * s }} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 14 * s, fontWeight: 600 }}>
          <span>Yumi</span>
          <span style={{ color: "#a0a0a8", fontWeight: 400, fontSize: 12 * s }}>maintenant</span>
        </div>
        <div style={{ fontSize: 13.5 * s, marginTop: 2 * s }}>Claude Code veut pousser sur GitHub</div>
        <div style={{ fontSize: 12 * s, color: "#a0a0a8" }}>Touche pour décider</div>
      </div>
    </div>
  );
};

/** The person's own first seconds (`filmed`), or a sign of where they go until filmed. */
const Footage: React.FC<{ readonly filmed: boolean }> = ({ filmed }) =>
  filmed ? (
    <Video src={staticFile("prises/beta/plan-reel.mp4")} muted style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
  ) : (
    <AbsoluteFill style={{ background: "#141418", alignItems: "center", justifyContent: "center", fontFamily: THEME.text, color: THEME.muted, fontSize: 40, textAlign: "center", padding: 120 }}>
      Ton plan filmé ici : quelqu'un fait défiler son iPhone, la notification de Yumi arrive, il la touche.
      <div style={{ fontSize: 28, marginTop: 30 }}>public/prises/beta/plan-reel.mp4</div>
    </AbsoluteFill>
  );

/** A desk at night, far out of focus. */
const Room: React.FC = () => (
  <AbsoluteFill style={{ background: "#060608" }}>
    <AbsoluteFill style={{ filter: "blur(60px)" }}>
      <div style={{ position: "absolute", left: "8%", top: "18%", width: "84%", height: "34%", borderRadius: 40, background: "linear-gradient(160deg, #1B2A4A, #3A2650 60%, #11131B)", opacity: 0.4 }} />
      <div style={{ position: "absolute", left: "-10%", top: "70%", width: "120%", height: "40%", background: "#141317" }} />
    </AbsoluteFill>
  </AbsoluteFill>
);

/** The MacBook, its screen showing the real island. */
const Mac: React.FC<{ readonly width: number; readonly source: number; readonly glow: number; readonly waiting: boolean }> = ({ width, source, glow, waiting }) => {
  const { fps } = useVideoConfig();
  const screen = width * (820 / 1920);
  return (
    <div style={{ position: "relative", width }}>
      <div
        style={{
          position: "relative",
          width,
          height: screen + width * 0.035,
          borderRadius: `${width * 0.03}px ${width * 0.03}px 0 0`,
          background: "#0d0d10",
          padding: width * 0.017,
          boxSizing: "border-box",
          boxShadow: `inset 0 0 0 2px rgba(255,255,255,0.08), 0 0 ${80 * glow}px rgba(180,155,255,${0.5 * glow})`,
        }}
      >
        <div style={{ width: "100%", height: "100%", borderRadius: width * 0.012, overflow: "hidden", position: "relative" }}>
          {/* Closer on the island: the top middle of the screen, larger */}
          <div style={{ position: "absolute", inset: 0, transformOrigin: "50% 0", scale: 2.8 }}>
            {waiting ? (
              <Img src={staticFile("prises/beta/ile-attente.png")} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
            ) : (
              <Video src={staticFile("prises/beta/ile-mac-liaison.mp4")} muted trimBefore={Math.round(source * fps)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
            )}
          </div>
        </div>
      </div>
      <div style={{ width: width * 1.09, marginLeft: -width * 0.045, height: width * 0.024, borderRadius: `0 0 ${width * 0.02}px ${width * 0.02}px`, background: "linear-gradient(#5a5b61, #2a2b30)" }} />
    </div>
  );
};

/** The stream from the iPhone to the Mac: points of light along a gentle arc. */
const Stream: React.FC<{ readonly from: { x: number; y: number }; readonly to: { x: number; y: number }; readonly t: number; readonly start: number; readonly end: number }> = ({
  from,
  to,
  t,
  start,
  end,
}) => {
  if (t < start || t > end + 0.8) return null;
  const mid = { x: (from.x + to.x) / 2, y: Math.min(from.y, to.y) - Math.abs(to.x - from.x) * 0.25 };
  const at = (p: number) => ({
    x: (1 - p) * (1 - p) * from.x + 2 * (1 - p) * p * mid.x + p * p * to.x,
    y: (1 - p) * (1 - p) * from.y + 2 * (1 - p) * p * mid.y + p * p * to.y,
  });
  const fade = 1 - ramp(t, end, end + 0.8);
  const show = ramp(t, start, start + 0.6);
  const dots = Array.from({ length: 14 }, (_, i) => {
    const p = ((t - start) * 0.55 + i / 14) % 1;
    return { ...at(p), o: Math.sin(p * Math.PI) };
  });
  const path = Array.from({ length: 40 }, (_, i) => at(i / 39));
  return (
    <svg style={{ position: "absolute", inset: 0, width: "100%", height: "100%", overflow: "visible", opacity: fade }}>
      <defs>
        <linearGradient id="wire" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0" stopColor="#5B8CFF" />
          <stop offset="1" stopColor="#F58AD9" />
        </linearGradient>
      </defs>
      <polyline points={path.map((p) => `${p.x},${p.y}`).join(" ")} fill="none" stroke="url(#wire)" strokeWidth={2} opacity={0.5 * show} />
      {dots.map((d, i) => (
        <circle key={i} cx={d.x} cy={d.y} r={5} fill="#fff" opacity={d.o * show} style={{ filter: "drop-shadow(0 0 8px #C77DFF)" }} />
      ))}
    </svg>
  );
};

export const Beta: React.FC<{ readonly filmed?: boolean; readonly reel?: boolean; readonly voice?: boolean }> = ({ filmed = false, reel = false, voice = false }) => {
  const { fps, width: VW, height: VH } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  const wide = VW > VH;
  const phoneWidth = wide ? 390 : 560;
  const scale = phoneWidth / PT.w;
  const phoneX = wide ? VW * 0.3 : VW / 2;
  const phoneY = wide ? VH * 0.5 : VH * 0.44;

  // Which shot, and the time inside it
  let start = 0;
  let index = -1;
  for (let i = 0; i < SHOTS.length; i++) {
    if (t < start + SHOTS[i].length) {
      index = i;
      break;
    }
    start += SHOTS[i].length;
  }
  const inLink = index === -1 && t < shotsLength + LINK;
  const shot = index >= 0 ? SHOTS[index] : null;
  const st = t - start;

  // A slow push toward what matters; a soft fade between shots
  const push = shot?.push ? ramp(st, shot.push.at, shot.push.at + 2.6) : 0;
  const zoom = 1 + (shot?.push ? (shot.push.zoom - 1) * push : 0);
  const focus = shot?.push ? { x: shot.push.x * scale, y: shot.push.y * scale } : { x: (PT.w / 2) * scale, y: (PT.h / 2) * scale };
  const fadeIn = shot ? ramp(st, 0, 0.45) : 1;
  const fadeOut = shot ? 1 - ramp(st, shot.length - 0.35, shot.length) : 1;
  const drift = Math.sin(t * 0.35) * 0.6;

  // The link: the phone and the Mac side by side
  const lt = t - shotsLength;
  const linkPhone = { x: wide ? VW * 0.22 : VW * 0.27, y: wide ? VH * 0.55 : VH * 0.6 };
  const macWidth = wide ? 980 : 620;
  const linkMac = { x: wide ? VW * 0.63 : VW * 0.6, y: wide ? VH * 0.38 : VH * 0.25 };

  const thumb = thumbAt(shot?.touches, st, phoneWidth);

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      {t < shotsLength + LINK ? (
        <>
          <Room />
          {reel && index === 0 ? (
            <Footage filmed={filmed} />
          ) : shot ? (
            <AbsoluteFill style={{ perspective: 2400 }}>
              <div
                style={{
                  position: "absolute",
                  left: phoneX,
                  top: phoneY,
                  transform: `translate(-50%, -50%) rotateX(${3 + drift}deg) rotateY(-4deg)`,
                  transformStyle: "preserve-3d",
                }}
              >
                <div style={{ transformOrigin: `${focus.x}px ${focus.y}px`, scale: zoom, position: "relative" }}>
                  <Grip width={phoneWidth} side="behind" thumb={thumb} />
                  <Phone width={phoneWidth}>
                    <AbsoluteFill style={{ opacity: Math.max(0.15, fadeIn * fadeOut) }}>
                      <Sequence key={index} from={Math.round(start * fps)} layout="none">
                        <Take name={shot.take} source={shot.source} />
                      </Sequence>
                    </AbsoluteFill>
                    {index === 0 ? <Banner t={st} at={6.2} scale={scale} /> : null}
                  </Phone>
                  <Grip width={phoneWidth} side="front" thumb={thumb} />
                </div>
              </div>
            </AbsoluteFill>
          ) : inLink ? (
            <AbsoluteFill style={{ opacity: ramp(lt, 0, 0.6) * (1 - ramp(lt, LINK - 0.4, LINK)) }}>
              <div style={{ position: "absolute", left: linkMac.x, top: linkMac.y, transform: "translate(-50%, -50%)" }}>
                {lt < 3.6 ? (
                  <Mac width={macWidth} source={0} glow={0} waiting />
                ) : (
                  <Sequence from={Math.round((shotsLength + 3.6) * fps)} layout="none">
                    <Mac width={macWidth} source={7.7} glow={ramp(lt, 3.9, 4.5) * (1 - ramp(lt, 9, 10.5))} waiting={false} />
                  </Sequence>
                )}
              </div>
              <div style={{ position: "absolute", left: linkPhone.x, top: linkPhone.y, transform: "translate(-50%, -50%) scale(0.6)" }}>
                <Phone width={phoneWidth}>
                  {lt < 3.6 ? (
                    <Img src={staticFile("prises/beta/connexion-attente.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
                  ) : (
                    <Sequence from={Math.round((shotsLength + 3.6) * fps)} layout="none">
                      <Take name="connexion" source={6.8} />
                    </Sequence>
                  )}
                </Phone>
              </div>
              <Stream
                from={{ x: linkPhone.x + phoneWidth * 0.18, y: linkPhone.y - phoneWidth * 0.5 }}
                to={{ x: linkMac.x, y: linkMac.y - (macWidth * (820 / 1920)) / 2 + macWidth * 0.05 }}
                t={lt}
                start={0.8}
                end={3.8}
              />
            </AbsoluteFill>
          ) : null}

          {/* The words, under the phone, or beside it on a computer */}
          {SHOTS.map((s, i) => {
            const from = SHOTS.slice(0, i).reduce((sum, x) => sum + x.length, 0);
            return (
              <Sequence key={s.take} from={Math.round(from * fps)} durationInFrames={Math.round(s.length * fps)} layout="none">
                <AbsoluteFill style={wide ? { left: VW * 0.44, width: VW * 0.52, top: VH * 0.42 } : { top: VH * 0.87 }}>
                  <Words lines={s.lines} enter={0.6} exit={s.length - 0.8} size={wide ? 46 : 50} />
                </AbsoluteFill>
              </Sequence>
            );
          })}
          <Sequence from={Math.round(shotsLength * fps)} durationInFrames={Math.round(LINK * fps)} layout="none">
            <AbsoluteFill style={{ top: VH * (wide ? 0.82 : 0.86) }}>
              <Words lines={["Ton iPhone se relie à ton Mac,", "par ton iCloud. Rien d'autre."]} enter={0.6} exit={LINK - 0.9} size={50} />
            </AbsoluteFill>
          </Sequence>
        </>
      ) : null}

      <Sequence from={Math.round((shotsLength + LINK) * fps)} layout="none">
        <Fin subtitle="Bêta. Gratuit." />
      </Sequence>

      {voice
        ? [...SHOTS.map((_, i) => SHOTS.slice(0, i).reduce((a, x) => a + x.length, 0) + 0.3), shotsLength + 0.4, shotsLength + LINK + 0.3].map((at, i) => (
            <Sequence key={i} from={Math.round(at * fps)} layout="none">
              <Audio src={staticFile(`voix/iphone-${i}.mp3`)} />
            </Sequence>
          ))
        : null}
      <Son name="pop" at={6.2} volume={0.6} />
      <Son name="blip" at={8.1} volume={0.5} />
      <Son name="greet" at={13.5} volume={0.6} />
      <Son name="approve" at={SHOTS[0].length + SHOTS[1].length + 3.15} volume={0.6} />
      <Son name="love" at={shotsLength + 3.8} volume={0.7} />
    </AbsoluteFill>
  );
};
