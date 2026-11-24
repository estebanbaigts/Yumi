import React from "react";
import { Video } from "@remotion/media";
import { AbsoluteFill, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Fin } from "../scenes/Fin";

// The film of the beta (design/video-beta.md): someone scrolls, a notification of Yumi comes,
// they open it, the app wakes, then the app shows itself, floating in depth, and meets the Mac.
// Every screen is a real take of the app in filming mode (public/prises/beta).
//
// `reel`: version 2, the first seconds are the person's own footage (prises/beta/plan-reel.mp4)
// instead of the phone in depth.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ramp = (t: number, a: number, b: number, ease = EASE.camera) => interpolate(t, [a, b], [0, 1], { ...CLAMP, easing: ease });

/** The takes are 1178 × 2556 (an iPhone 16 at 3×). */
const SCREEN = { w: 560, h: 560 * (2556 / 1178) };
const BEZEL = 16;
export const BETA_LENGTH = 30.3;

/** A take of the app, from `source` seconds, inside the phone's screen. */
const Take: React.FC<{ readonly name: string; readonly source: number; readonly rate?: number }> = ({ name, source, rate = 1 }) => {
  const { fps } = useVideoConfig();
  return (
    <Video
      src={staticFile(`prises/beta/${name}.mp4`)}
      muted
      trimBefore={Math.round(source * fps)}
      playbackRate={rate}
      style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }}
    />
  );
};

/** The iPhone as an object: titanium edge, black glass, a light that slides on the glass as it turns. */
const Phone: React.FC<{
  readonly rx?: number;
  readonly ry?: number;
  readonly rz?: number;
  readonly x?: number;
  readonly y?: number;
  readonly scale?: number;
  readonly children: React.ReactNode;
}> = ({ rx = 0, ry = 0, rz = 0, x = 0, y = 0, scale = 1, children }) => {
  const W = SCREEN.w + BEZEL * 2;
  const H = SCREEN.h + BEZEL * 2;
  // The glare follows the turn: light coming from the upper left
  const glare = 50 + ry * 2.2 - rx * 1.2;
  return (
    <div
      style={{
        position: "absolute",
        left: 540 - W / 2,
        top: 960 - H / 2,
        width: W,
        height: H,
        transform: `translate(${x}px, ${y}px) scale(${scale}) rotateX(${rx}deg) rotateY(${ry}deg) rotateZ(${rz}deg)`,
        transformStyle: "preserve-3d",
      }}
    >
      {/* The shadow on the ground, under and behind it */}
      <div
        style={{
          position: "absolute",
          inset: 40,
          borderRadius: 120,
          background: "rgba(0,0,0,0.85)",
          filter: "blur(70px)",
          transform: `translateZ(-120px) translate(${-ry * 3}px, ${60 + rx * 3}px)`,
        }}
      />
      {/* The edge */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          borderRadius: 92,
          background: "linear-gradient(140deg, #4a4b52 0%, #1b1c20 30%, #0d0d10 60%, #3a3b40 100%)",
          boxShadow: "inset 0 0 0 2px rgba(255,255,255,0.08), 0 40px 120px rgba(0,0,0,0.6)",
        }}
      />
      {/* The screen */}
      <div
        style={{
          position: "absolute",
          left: BEZEL,
          top: BEZEL,
          width: SCREEN.w,
          height: SCREEN.h,
          borderRadius: 78,
          overflow: "hidden",
          background: "#000",
        }}
      >
        {children}
        {/* The glass: one soft reflection that moves with the turn */}
        <div
          style={{
            position: "absolute",
            inset: 0,
            background: `linear-gradient(115deg, transparent ${glare - 18}%, rgba(255,255,255,0.07) ${glare}%, transparent ${glare + 14}%)`,
            pointerEvents: "none",
          }}
        />
      </div>
    </div>
  );
};

/** A desk at night, out of focus: the Mac's screen far behind, a lamp, the depth of the room. */
const Room: React.FC<{ readonly blur: number; readonly glow: number }> = ({ blur, glow }) => (
  <AbsoluteFill style={{ background: "#07070a" }}>
    <AbsoluteFill style={{ filter: `blur(${blur}px)` }}>
      {/* The Mac, far behind, its screen lit */}
      <div style={{ position: "absolute", left: 120, top: 380, width: 840, height: 520, borderRadius: 30, background: "linear-gradient(160deg, #1B2A4A, #3A2650 60%, #11131B)", opacity: 0.55 * glow }} />
      <div style={{ position: "absolute", left: 470, top: 380, width: 140, height: 26, borderRadius: "0 0 14px 14px", background: "#000", opacity: glow }} />
      {/* A warm lamp on the side */}
      <div style={{ position: "absolute", left: 830, top: 180, width: 260, height: 260, borderRadius: "50%", background: "#F2B36B", opacity: 0.22 * glow }} />
      {/* The table */}
      <div style={{ position: "absolute", left: -100, top: 1320, width: 1280, height: 700, background: "linear-gradient(#17161a, #0b0b0d)" }} />
    </AbsoluteFill>
  </AbsoluteFill>
);

/** A notification of Yumi, as iOS draws it on the screen. */
const Banner: React.FC<{ readonly t: number; readonly at: number }> = ({ t, at }) => {
  const { fps } = useVideoConfig();
  const p = spring({ frame: Math.max(0, (t - at) * fps), fps, config: { damping: 15, stiffness: 140 } });
  return (
    <div
      style={{
        position: "absolute",
        left: 18,
        right: 18,
        top: 60,
        padding: "18px 20px",
        borderRadius: 34,
        background: "rgba(40,40,46,0.82)",
        backdropFilter: "blur(30px)",
        display: "flex",
        gap: 16,
        alignItems: "center",
        transform: `translateY(${(1 - p) * -170}px) scale(${0.92 + 0.08 * p})`,
        opacity: Math.min(1, p * 1.4),
        fontFamily: THEME.text,
        color: THEME.fg,
      }}
    >
      <img src={staticFile("prises/beta/icone.png")} style={{ width: 58, height: 58, borderRadius: 14 }} />
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontSize: 21, fontWeight: 600 }}>
          <span>Yumi</span>
          <span style={{ color: "#a0a0a8", fontWeight: 400, fontSize: 18 }}>maintenant</span>
        </div>
        <div style={{ fontSize: 20, marginTop: 3, color: "#e6e6ea" }}>Claude Code veut pousser sur GitHub</div>
        <div style={{ fontSize: 18, marginTop: 2, color: "#a0a0a8" }}>Touche pour décider</div>
      </div>
    </div>
  );
};

/** The person's own first seconds (version 2), or a sign saying where they go until filmed. */
const Footage: React.FC<{ readonly filmed: boolean }> = ({ filmed }) =>
  filmed ? (
    <Video
      src={staticFile("prises/beta/plan-reel.mp4")}
      muted
      style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }}
    />
  ) : (
    <AbsoluteFill style={{ background: "#141418", alignItems: "center", justifyContent: "center", fontFamily: THEME.text, color: THEME.muted, fontSize: 40, textAlign: "center", padding: 120 }}>
      Ton plan filmé ici (4 s) : quelqu'un fait défiler son iPhone, la notification de Yumi arrive, il la touche.
      <div style={{ fontSize: 28, marginTop: 30 }}>public/prises/beta/plan-reel.mp4</div>
    </AbsoluteFill>
  );

/** The MacBook, the top of its screen showing the real island. */
const Mac: React.FC<{ readonly x: number; readonly ry: number; readonly scale: number; readonly source: number }> = ({ x, ry, scale, source }) => {
  const { fps } = useVideoConfig();
  const W = 900;
  const H = W * (820 / 1920);
  return (
    <div style={{ position: "absolute", left: 540 - W / 2, top: 700, width: W, transform: `translateX(${x}px) scale(${scale}) rotateY(${ry}deg)`, transformStyle: "preserve-3d" }}>
      <div style={{ position: "absolute", inset: -40, top: 60, borderRadius: 60, background: "rgba(0,0,0,0.8)", filter: "blur(60px)", transform: "translateZ(-100px) translateY(80px)" }} />
      <div style={{ position: "relative", width: W, height: H + 30, borderRadius: "28px 28px 0 0", background: "#0d0d10", padding: 15, boxShadow: "inset 0 0 0 2px rgba(255,255,255,0.08)" }}>
        <div style={{ width: "100%", height: H, borderRadius: 14, overflow: "hidden", position: "relative" }}>
          <Video src={staticFile("prises/beta/ile-mac.mp4")} muted trimBefore={Math.round(source * fps)} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        </div>
      </div>
      <div style={{ width: W + 80, marginLeft: -40, height: 22, borderRadius: "0 0 18px 18px", background: "linear-gradient(#5a5b61, #2a2b30)" }} />
    </div>
  );
};

/** One feature: the phone turns to it, a line says it. */
const FEATURES = [
  { take: "agents", source: 8.6, lines: ["Tes agents demandent.", "Tu réponds de ta poche."] },
  { take: "parler", source: 8.7, lines: ["Il réfléchit", "avec ton Claude Code."] },
  { take: "aujourdhui", source: 9.2, lines: ["Ta journée,", "à ta façon."] },
  { take: "meteo", source: 9.0, lines: ["Et il a", "son caractère."] },
] as const;
const FEATURE_START = 9.4;
const FEATURE_LENGTH = 3.0;

export const Beta: React.FC<{ readonly reel?: boolean; readonly filmed?: boolean }> = ({ reel = false, filmed = false }) => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;

  // ── 0 to 4 s: the phone in the room, a notification, the camera goes to it, a touch
  const push = ramp(t, 1.9, 3.6);
  const intro = t < 4.2;
  // ── 4 to 9.4 s: the opening of the app, the phone facing us, close
  const open = ramp(t, 3.6, 4.6);
  // ── features: a slow turn, one way then the other
  const fi = Math.max(0, Math.min(FEATURES.length - 1, Math.floor((t - FEATURE_START) / FEATURE_LENGTH)));
  const ft = (t - FEATURE_START - fi * FEATURE_LENGTH) / FEATURE_LENGTH;
  const inFeatures = t >= FEATURE_START && t < FEATURE_START + FEATURES.length * FEATURE_LENGTH;
  const side = fi % 2 === 0 ? 1 : -1;
  // ── 21.4 s: the Mac comes in, the phone steps aside
  const meet = ramp(t, 21.4, 22.6);
  const end = 26.9;

  let phone: { rx: number; ry: number; rz: number; x: number; y: number; scale: number };
  if (intro) {
    // Held a little low, tilted, then brought to the face of the camera
    phone = {
      rx: 22 * (1 - push) + 4 * Math.sin(t * 0.8),
      ry: -18 * (1 - push),
      rz: -6 * (1 - push),
      x: 40 * (1 - push),
      y: 160 * (1 - push) + 420 * push,
      scale: 0.82 + 1.25 * push,
    };
  } else if (!inFeatures && t < FEATURE_START) {
    // The opening: very close at first (the island), then back to the whole phone
    phone = { rx: 0, ry: 0, rz: 0, x: 0, y: 420 * (1 - open) + 40 * open, scale: 2.07 - 1.07 * ramp(t, 7.6, 9.2) - 0.05 * open };
  } else if (inFeatures) {
    const swing = interpolate(ft, [0, 0.22, 0.85, 1], [side * 26, side * 6, side * -4, -side * 18], { ...CLAMP, easing: EASE.camera });
    phone = { rx: 6 + 3 * Math.sin(t), ry: swing, rz: 0, x: -swing * 4, y: 40 + 10 * Math.sin(t * 1.3), scale: 0.95 };
  } else {
    phone = { rx: 4, ry: 18 * meet, rz: 0, x: -300 * meet, y: 40 - 40 * meet, scale: 0.95 - 0.42 * meet };
  }

  const screen = intro ? (
    <>
      <img src={staticFile("prises/beta/accueil.png")} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
      <Banner t={t} at={1.2} />
    </>
  ) : t < FEATURE_START ? (
    <Sequence from={Math.round(4.2 * fps)} layout="none">
      <Take name="lancement" source={0.6} />
    </Sequence>
  ) : inFeatures ? (
    <Sequence key={fi} from={Math.round((FEATURE_START + fi * FEATURE_LENGTH) * fps)} layout="none">
      <Take name={FEATURES[fi].take} source={FEATURES[fi].source} />
    </Sequence>
  ) : (
    <Sequence from={Math.round(21.4 * fps)} layout="none">
      <Take name="connexion" source={6.6} />
    </Sequence>
  );

  // A touch on the notification
  const tap = ramp(t, 3.35, 3.75, EASE.out);

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      {t < end ? (
        <>
          {reel && intro ? (
            <Footage filmed={filmed} />
          ) : (
            <>
              <Room blur={18 + 30 * push} glow={1 - 0.7 * ramp(t, 3.6, 4.4)} />
              <AbsoluteFill style={{ perspective: 2200 }}>
                <Phone {...phone}>{screen}</Phone>
              </AbsoluteFill>
              {intro && t > 3.3 ? (
                <div
                  style={{
                    position: "absolute",
                    left: 540 - 60,
                    top: 600 - 60,
                    width: 120,
                    height: 120,
                    borderRadius: "50%",
                    background: "rgba(255,255,255,0.35)",
                    transform: `scale(${0.4 + 1.2 * tap})`,
                    opacity: 1 - tap,
                  }}
                />
              ) : null}
              {t >= 21.4 ? <Mac x={170 * meet + (1 - meet) * 900} ry={-14 * meet} scale={0.8} source={15.5 + (t - 21.4) * 0.8} /> : null}
            </>
          )}

          {/* The words, on a shade that keeps them readable over a screen */}
          <AbsoluteFill style={{ background: "linear-gradient(transparent 70%, rgba(0,0,0,0.75) 88%)", pointerEvents: "none" }} />
          <Sequence from={Math.round(0.5 * fps)} durationInFrames={Math.round(3.4 * fps)} layout="none">
            <AbsoluteFill style={{ top: 1520 }}>
              <Words lines={["Yumi a quelque chose", "à te dire."]} enter={0.9} exit={2.9} size={64} />
            </AbsoluteFill>
          </Sequence>
          {FEATURES.map((f, i) => (
            <Sequence key={f.take} from={Math.round((FEATURE_START + i * FEATURE_LENGTH) * fps)} durationInFrames={Math.round(FEATURE_LENGTH * fps)} layout="none">
              <AbsoluteFill style={{ top: 1620 }}>
                <Words lines={f.lines} enter={0.25} exit={FEATURE_LENGTH - 0.45} size={58} />
              </AbsoluteFill>
            </Sequence>
          ))}
          <Sequence from={Math.round(21.8 * fps)} durationInFrames={Math.round(5 * fps)} layout="none">
            <AbsoluteFill style={{ top: 1560 }}>
              <Words lines={["Ton iPhone et ton Mac", "se parlent."]} enter={0.3} exit={4.5} size={60} />
            </AbsoluteFill>
          </Sequence>
        </>
      ) : null}

      <Sequence from={Math.round(end * fps)} layout="none">
        <Fin subtitle="Bêta. Gratuit." />
      </Sequence>

      <Son name="pop" at={1.2} volume={0.6} />
      <Son name="blip" at={3.4} volume={0.5} />
      <Son name="greet" at={8.0} volume={0.7} />
      <Son name="approve" at={10.2} volume={0.6} />
      <Son name="love" at={23.0} volume={0.7} />
    </AbsoluteFill>
  );
};
