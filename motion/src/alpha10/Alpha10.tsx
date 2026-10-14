import React from "react";
import { Audio } from "@remotion/media";
import { AbsoluteFill, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Bord, Ecran, arrivee } from "../scenes/Fonctions";
import { EYES, NOTCH, SIZE, YUMI_AT } from "../scenes/stage";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";

// The alpha 10 reel (Instagram, TikTok): Yumi works for everyone, free, with no account.
//
// He is born in the dark and leaves into the notch; the real island opens on him (the takes
// filmed with `YUMI_STUDIO=1`); he answers, asks before acting, keeps the beat, lives his
// moods; then he comes back out of the notch to say it is free, and stays.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** Every part, in seconds, back to back. */
const PARTS = {
  hook: 3.4,
  launch: 4.2,
  chat: 5.8,
  permission: 5.0,
  warn: 3.4,
  pause: 3.4,
  mail: 6.0,
  back: 4.4,
  end: 3.6,
} as const;

type Part = keyof typeof PARTS;
const ORDER = Object.keys(PARTS) as Part[];
const START = ORDER.reduce<Record<string, number>>((acc, part, i) => {
  acc[part] = i === 0 ? 0 : acc[ORDER[i - 1]] + PARTS[ORDER[i - 1]];
  return acc;
}, {}) as Record<Part, number>;

export const ALPHA10_LENGTH = ORDER.reduce((sum, part) => sum + PARTS[part], 0);

const Part: React.FC<{ readonly part: Part; readonly children: React.ReactNode }> = ({ part, children }) => {
  const { fps } = useVideoConfig();
  return (
    <Sequence name={part} from={Math.round(START[part] * fps)} durationInFrames={Math.round(PARTS[part] * fps)} premountFor={fps}>
      {children}
    </Sequence>
  );
};

const useT = () => useCurrentFrame() / useVideoConfig().fps;

/** The small mark at the top that says which film this is. */
const Tag: React.FC<{ readonly enter?: number }> = ({ enter = 0.1 }) => {
  const t = useT();
  return (
    <div
      style={{
        position: "absolute",
        top: 170,
        left: 0,
        right: 0,
        textAlign: "center",
        fontFamily: THEME.text,
        fontSize: 30,
        fontWeight: 600,
        letterSpacing: "0.32em",
        color: THEME.muted,
        opacity: interpolate(t, [enter, enter + 0.5], [0, 1], CLAMP),
      }}
    >
      YUMI · ALPHA 10
    </div>
  );
};

/** Captions under the window: a small step label, then the line. */
const Caption: React.FC<{
  readonly step: string;
  readonly lines: readonly string[];
  readonly enter?: number;
  readonly exit?: number;
}> = ({ step, lines, enter = 0.25, exit }) => {
  const t = useT();
  const out = exit === undefined ? 1 : interpolate(t, [exit, exit + 0.3], [1, 0], CLAMP);
  return (
    <AbsoluteFill style={{ top: 820 }}>
      <div
        style={{
          textAlign: "center",
          fontFamily: THEME.text,
          fontSize: 28,
          fontWeight: 700,
          letterSpacing: "0.28em",
          color: "#B9A6FF",
          opacity: interpolate(t, [enter - 0.1, enter + 0.3], [0, 1], CLAMP) * out,
          marginBottom: 26,
        }}
      >
        {step}
      </div>
      <Words lines={lines} enter={enter} exit={exit} size={86} style={{ fontWeight: 700 }} />
    </AbsoluteFill>
  );
};

/** A take in the window, settling in after a cut, the camera easing from one framing to another. */
const Plan: React.FC<{
  readonly take: string;
  readonly source: number;
  readonly rate?: number;
  readonly focus: readonly [number, number];
  readonly from: number;
  readonly to: number;
  readonly first?: boolean;
  readonly click?: number;
  /** Where the click lands, in the window, before the camera moves. */
  readonly target?: readonly [number, number];
}> = ({ take, source, rate, focus, from, to, first, click, target = focus }) => {
  const t = useT();
  const { durationInFrames, fps } = useVideoConfig();
  const length = durationInFrames / fps;
  const scale = interpolate(t, [0, length], [from, to], { ...CLAMP, easing: EASE.camera });
  const style = first
    ? arrivee(t)
    : {
        opacity: interpolate(t, [0, 0.2], [0, 1], CLAMP),
        scale: interpolate(t, [0, 0.55], [1.06, 1], { ...CLAMP, easing: EASE.out }),
        filter: `blur(${interpolate(t, [0, 0.3], [10, 0], CLAMP)}px)`,
      };
  return (
    <>
      <Ecran take={take} source={source} rate={rate} focus={focus} scale={scale} style={style}>
        {click !== undefined ? (
          <div
            style={{
              position: "absolute",
              // The camera scales the take around `focus`: the target moves away from it
              left: focus[0] + (target[0] - focus[0]) * scale,
              top: focus[1] + (target[1] - focus[1]) * scale,
              width: interpolate(t, [click, click + 0.6], [50, 230], { ...CLAMP, easing: EASE.out }),
              aspectRatio: "1",
              translate: "-50% -50%",
              borderRadius: "50%",
              border: "4px solid #3DDC97",
              opacity: interpolate(t, [click, click + 0.06, click + 0.6], [0, 0.95, 0], CLAMP),
            }}
          />
        ) : null}
        {/* The desktop under the island fades to black: only the island and the notch remain */}
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: 0,
            height: 470,
            background: "linear-gradient(to bottom, rgba(0,0,0,0), #000 45%)",
          }}
        />
      </Ecran>
      <Bord />
    </>
  );
};

/** Him alone, big, in the dark. */
const Alone: React.FC<{ readonly script: YumiScript; readonly style?: React.CSSProperties }> = ({ script, style }) => (
  <AbsoluteFill style={style}>
    <Yumi script={script} size={SIZE} style={YUMI_AT} />
  </AbsoluteFill>
);

/** From his place to the notch (`k` 0 → 1), shrinking and blurring as he goes up into it. */
const toNotch = (k: number): React.CSSProperties => ({
  transformOrigin: `${EYES.x}px ${EYES.y}px`,
  translate: `${(NOTCH.x - EYES.x) * k}px ${(NOTCH.y - 10 - EYES.y) * k}px`,
  scale: interpolate(k, [0, 1], [1, 0.1]),
  filter: `blur(${interpolate(k, [0.4, 1], [0, 6], CLAMP)}px)`,
  opacity: interpolate(k, [0.85, 1], [1, 0], CLAMP),
});

// ---------------------------------------------------------------------------------------------

const HOOK: YumiScript = {
  seed: 10,
  cues: [
    { at: 0, lit: false, mood: "asleep" },
    { at: 0.5, mood: "neutral", blink: true },
    { at: 0.9, lit: true, mood: "curious", gaze: [0, -0.6] },
    { at: 1.7, mood: "happy", gaze: [0, -1] },
    { at: 2.4, pose: "jump" },
  ],
};

const Hook: React.FC = () => {
  const t = useT();
  const leave = interpolate(t, [2.55, 3.3], [0, 1], { ...CLAMP, easing: EASE.in });
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <Alone script={HOOK} style={toNotch(leave)} />
      {/* The notch he goes into: a thin black lip at the top of a screen that lights up */}
      <div
        style={{
          position: "absolute",
          left: NOTCH.x - 150,
          top: 0,
          width: 300,
          height: 46,
          borderRadius: "0 0 26px 26px",
          background: "#000",
          boxShadow: `0 0 0 2px rgba(185,166,255,${interpolate(t, [2.2, 2.8], [0, 0.55], CLAMP)})`,
        }}
      />
      <AbsoluteFill style={{ top: 1250 }}>
        <Words lines={["Ton Mac a une encoche."]} enter={0.35} exit={1.55} size={78} style={{ fontWeight: 700 }} />
      </AbsoluteFill>
      <AbsoluteFill style={{ top: 1250 }}>
        <Words lines={["Quelqu'un vit dedans."]} enter={1.75} exit={2.75} size={78} style={{ fontWeight: 700, color: "#CFC2FF" }} />
      </AbsoluteFill>
      <Son name="peek" at={0.5} />
      <Son name="greet" at={1.7} volume={0.6} />
      <Son name="send" at={2.6} volume={0.7} />
    </AbsoluteFill>
  );
};

/** All the takes come from one run of the alpha 10 filming mode (prises/alpha10.mp4). */
const TAKE = "alpha10";

const Launch: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Tag />
    <Plan take={TAKE} source={1.6} focus={[500, 110]} from={1.9} to={1.3} first />
    <Caption step="VOICI YUMI" lines={["Il vit en haut", "de ton Mac."]} enter={0.5} exit={3.75} />
    <Son name="open" at={0.2} />
  </AbsoluteFill>
);

const Chat: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Tag enter={0} />
    <Plan take={TAKE} source={13.5} rate={1.35} focus={[500, 130]} from={1.18} to={1.3} />
    <Caption step="1 · TU LUI DEMANDES" lines={["Avec tes mots."]} enter={0.3} exit={2.6} />
    <Caption step="1 · TU LUI DEMANDES" lines={["Il le fait."]} enter={3.0} exit={5.35} />
    <Son name="send" at={0.4} />
    <Son name="finish" at={4.4} volume={0.6} />
  </AbsoluteFill>
);

const Permission: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Tag enter={0} />
    <Plan take={TAKE} source={24.0} focus={[500, 114]} from={1.0} to={1.1} click={2.45} target={[890, 114]} />
    <Caption step="2 · TU DÉCIDES" lines={["Rien ne change", "sans ton clic."]} enter={0.3} exit={4.55} />
    <Son name="approval" at={0.3} volume={0.6} />
    <Son name="approve" at={2.45} />
  </AbsoluteFill>
);

const Warn: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Tag enter={0} />
    <Plan take={TAKE} source={35.6} focus={[500, 130]} from={1.32} to={1.22} />
    <Caption step="3 · IL VEILLE SUR TOI" lines={["Ta réunion arrive…"]} enter={0.25} exit={2.95} />
    <Son name="question" at={0.3} volume={0.5} />
  </AbsoluteFill>
);

const Pause: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Tag enter={0} />
    <Plan take={TAKE} source={40.2} focus={[500, 55]} from={1.9} to={2.1} />
    <Caption step="3 · IL VEILLE SUR TOI" lines={["…et te dit", "de souffler."]} enter={0.2} exit={2.95} />
    <Son name="peek" at={0.2} volume={0.6} />
  </AbsoluteFill>
);

const Mail: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Tag enter={0} />
    <Plan take={TAKE} source={53.6} rate={1.4} focus={[500, 160]} from={1.18} to={1.3} />
    <Caption step="4 · TES MAILS" lines={["Il prépare", "ta réponse."]} enter={0.3} exit={2.9} />
    <Caption step="4 · TES MAILS" lines={["Tu l'envoies", "si tu veux."]} enter={3.2} exit={5.55} />
    <Son name="search" at={0.4} volume={0.5} />
    <Son name="finish" at={2.6} volume={0.5} />
  </AbsoluteFill>
);

const BACK: YumiScript = {
  seed: 11,
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.1, pose: "boing" },
    { at: 2.4, mood: "wink" },
    { at: 2.9, mood: "happy" },
  ],
};

const Back: React.FC = () => {
  const t = useT();
  const come = interpolate(t, [0, 0.9], [1, 0], { ...CLAMP, easing: EASE.spring });
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <Alone script={BACK} style={toNotch(come)} />
      <AbsoluteFill style={{ top: 1230 }}>
        <Words lines={["Gratuit.", "Sans compte."]} enter={0.85} exit={3.95} size={104} style={{ fontWeight: 700 }} />
        <Words
          lines={["Et tout reste sur ton Mac."]}
          enter={1.6}
          exit={3.95}
          size={50}
          style={{ fontWeight: 500, color: THEME.muted, marginTop: 30 }}
        />
      </AbsoluteFill>
      <Son name="pop" at={0.1} />
      <Son name="proud" at={1.1} volume={0.6} />
      <Son name="wink" at={2.4} />
    </AbsoluteFill>
  );
};

const END: YumiScript = {
  seed: 12,
  cues: [
    { at: 0, mood: "happy", gaze: [0, 0.4] },
    { at: 1.4, mood: "curious", gaze: [0, 0.9] },
  ],
};

const End: React.FC = () => {
  const t = useT();
  const up = interpolate(t, [0, 0.8], [0, 1], { ...CLAMP, easing: EASE.camera });
  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <AbsoluteFill
        style={{
          transformOrigin: `${EYES.x}px ${EYES.y}px`,
          translate: `0 ${-260 * up}px`,
          scale: interpolate(up, [0, 1], [1, 0.62]),
        }}
      >
        <Yumi script={END} size={SIZE} style={YUMI_AT} />
      </AbsoluteFill>
      <AbsoluteFill style={{ top: 1000 }}>
        <Words lines={["Yumi."]} by="letter" enter={0.35} size={190} style={{ fontWeight: 700 }} />
        <Words lines={["Alpha 10 · pour Mac"]} enter={0.75} size={50} style={{ fontWeight: 500, color: THEME.muted, marginTop: 10 }} />
      </AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 1500,
          display: "flex",
          justifyContent: "center",
          opacity: interpolate(t, [1.1, 1.5], [0, 1], CLAMP),
          translate: `0 ${interpolate(t, [1.1, 1.7], [30, 0], { ...CLAMP, easing: EASE.out })}px`,
        }}
      >
        <div
          style={{
            padding: "30px 60px",
            borderRadius: 999,
            background: THEME.fg,
            color: "#000",
            fontFamily: THEME.text,
            fontSize: 46,
            fontWeight: 700,
          }}
        >
          Lien en bio
        </div>
      </div>
      <Son name="blip" at={1.15} volume={0.6} />
    </AbsoluteFill>
  );
};

const SCENES: Record<Part, React.FC> = {
  hook: Hook,
  launch: Launch,
  chat: Chat,
  permission: Permission,
  warn: Warn,
  pause: Pause,
  mail: Mail,
  back: Back,
  end: End,
};

export const Alpha10: React.FC = () => (
  <AbsoluteFill style={{ backgroundColor: THEME.black }}>
    <Audio src={staticFile("musique/ambiance.wav")} volume={0.5} />
    {ORDER.map((part) => {
      const Scene = SCENES[part];
      return (
        <Part key={part} part={part}>
          <Scene />
        </Part>
      );
    })}
  </AbsoluteFill>
);

