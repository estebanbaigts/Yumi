import React from "react";
import { Audio } from "@remotion/media";
import {
  AbsoluteFill,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { Son } from "../son/Son";
import { EASE, THEME } from "../theme";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { Habit } from "../yumi/blob";
import type { Cue, YumiScript } from "../yumi/engine";
import type { Mood, RimTone } from "../yumi/faces";
import type { SkinName } from "../yumi/skins";
import type { Lang } from "./Carousel";

// The carousel as a film (1080 × 1920): one Yumi, big, who changes costume on the beat, then
// mood, while the name of each one arrives under him; then his habits come in one by one
// around the frame; then the end. Same words as the stills, in French and in English.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** The parts, in seconds. */
const INTRO = 2.4;
const STEP = 0.62;
const SKINS: readonly {
  readonly name: SkinName;
  readonly fr: string;
  readonly en: string;
}[] = [
  { name: "bonnet", fr: "Le bonnet", en: "The beanie" },
  { name: "aureole", fr: "L'auréole", en: "The halo" },
  { name: "cornes", fr: "Les cornes", en: "The horns" },
  { name: "lunettes", fr: "Les lunettes", en: "The glasses" },
  { name: "pousse", fr: "La pousse", en: "The sprout" },
  { name: "casquette", fr: "La casquette", en: "The cap" },
  { name: "noeud", fr: "Le nœud pap'", en: "The bow tie" },
  { name: "moustache", fr: "La moustache", en: "The moustache" },
];
const MOODS: readonly {
  readonly mood: Mood;
  readonly rim: RimTone;
  readonly fr: string;
  readonly en: string;
}[] = [
  { mood: "happy", rim: "joy", fr: "Content", en: "Happy" },
  { mood: "curious", rim: "think", fr: "Curieux", en: "Curious" },
  { mood: "surprised", rim: "warn", fr: "Surpris", en: "Surprised" },
  { mood: "worried", rim: "warn", fr: "Inquiet", en: "Worried" },
  { mood: "annoyed", rim: "error", fr: "Agacé", en: "Annoyed" },
  { mood: "wink", rim: "calm", fr: "Complice", en: "Cheeky" },
];
const HABITS: readonly {
  readonly habit: Habit;
  readonly fr: string;
  readonly en: string;
}[] = [
  { habit: "coffee", fr: "Un café", en: "A coffee" },
  { habit: "matcha", fr: "Un matcha", en: "A matcha" },
  { habit: "headphones", fr: "Sa musique", en: "His music" },
  { habit: "sunglasses", fr: "Les lunettes", en: "Shades on" },
  { habit: "cloud", fr: "Un nuage", en: "A cloud" },
  { habit: "sleep", fr: "Une sieste", en: "A nap" },
];

const COSTUMES_AT = INTRO;
const COSTUMES_END = COSTUMES_AT + 0.7 + SKINS.length * STEP;
const MOODS_AT = COSTUMES_END + 0.2;
const MOODS_END = MOODS_AT + 0.7 + MOODS.length * (STEP + 0.08);
const HABITS_AT = MOODS_END + 0.2;
const HABITS_END = HABITS_AT + 5.0;
const END_AT = HABITS_END;
export const CAROUSEL_MOTION_LENGTH = END_AT + 3.6;

const TEXT = {
  fr: {
    kicker: "YUMI · ALPHA 10",
    intro: "Il a du caractère.",
    costumes: "1 · SES COSTUMES",
    moods: "2 · SES HUMEURS",
    habits: "3 · SES HABITUDES",
    habitsTitle: ["Pendant qu'un", "agent bosse."],
    end: ["Gratuit,", "pour Mac."],
    endSub: "Sans compte. Tout reste sur ton Mac.",
    cta: "Lien en bio",
    count: (n: number) => `${n} sur ${SKINS.length}`,
  },
  en: {
    kicker: "YUMI · ALPHA 10",
    intro: "He has character.",
    costumes: "1 · COSTUMES",
    moods: "2 · MOODS",
    habits: "3 · HABITS",
    habitsTitle: ["While an", "agent works."],
    end: ["Free,", "for Mac."],
    endSub: "No account. Everything stays on your Mac.",
    cta: "Link in bio",
    count: (n: number) => `${n} of ${SKINS.length}`,
  },
} as const;

/** The big Yumi's whole life in the film: costumes on the beat, then moods. */
const BIG: YumiScript = {
  seed: 31,
  cues: [
    { at: 0, mood: "asleep", lit: false },
    { at: 0.35, mood: "neutral", blink: true },
    { at: 0.7, lit: true, mood: "happy", rim: "joy", pose: "arrive" },
    { at: 1.6, mood: "wink" },
    { at: 2.0, mood: "happy" },
    ...SKINS.map<Cue>((s, i) => ({
      at: COSTUMES_AT + 0.7 + i * STEP,
      skin: s.name,
      pose: "pop",
      mood: i % 3 === 2 ? "wink" : "happy",
    })),
    { at: MOODS_AT + 0.5, skin: null, rim: "calm", mood: "neutral" },
    ...MOODS.map<Cue>((m, i) => ({
      at: MOODS_AT + 0.7 + i * (STEP + 0.08),
      mood: m.mood,
      rim: m.rim,
      pose: i === 2 ? "jump" : undefined,
    })),
  ],
};

const BIG_SIZE = 720;
const BIG_X = 540;
const BIG_Y = 860;

const useT = () => useCurrentFrame() / useVideoConfig().fps;

/** A label that pops under him for its own beat: up from a mask, then up and away. */
const Beat: React.FC<{
  readonly text: string;
  readonly at: number;
  readonly until: number;
  readonly size?: number;
  readonly color?: string;
  readonly top?: number;
}> = ({ text, at, until, size = 92, color = THEME.fg, top = 1300 }) => {
  const t = useT();
  if (t < at - 0.05 || t > until + 0.2) return null;
  const inK = interpolate(t, [at, at + 0.28], [0, 1], {
    ...CLAMP,
    easing: EASE.out,
  });
  const outK = interpolate(t, [until, until + 0.18], [0, 1], {
    ...CLAMP,
    easing: EASE.in,
  });
  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        top,
        height: size * 1.3,
        overflow: "hidden",
        textAlign: "center",
      }}
    >
      <div
        style={{
          fontFamily: THEME.text,
          fontSize: size,
          fontWeight: 700,
          letterSpacing: "-0.02em",
          color,
          translate: `0 ${(1 - inK) * size * 1.1 - outK * size * 1.1}px`,
        }}
      >
        {text}
      </div>
    </div>
  );
};

const Kicker: React.FC<{
  readonly text: string;
  readonly at: number;
  readonly until: number;
}> = ({ text, at, until }) => {
  const t = useT();
  const k =
    interpolate(t, [at, at + 0.4], [0, 1], CLAMP) *
    interpolate(t, [until, until + 0.3], [1, 0], CLAMP);
  if (k <= 0) return null;
  return (
    <div
      style={{
        position: "absolute",
        top: 250,
        left: 0,
        right: 0,
        textAlign: "center",
        fontFamily: THEME.text,
        fontSize: 32,
        fontWeight: 700,
        letterSpacing: `${0.2 + 0.12 * k}em`,
        color: "#B9A6FF",
        opacity: k,
      }}
    >
      {text}
    </div>
  );
};

/** One habit in the grid: he springs in from below, his routine already running. */
const HabitSeat: React.FC<{
  readonly habit: Habit;
  readonly label: string;
  readonly i: number;
  readonly lang: Lang;
}> = ({ habit, label, i }) => {
  const t = useT();
  const at = HABITS_AT + 0.6 + i * 0.28;
  const k = interpolate(t, [at, at + 0.55], [0, 1], {
    ...CLAMP,
    easing: EASE.spring,
  });
  const out = interpolate(t, [HABITS_END - 0.35, HABITS_END], [1, 0], CLAMP);
  const col = i % 2;
  const row = Math.floor(i / 2);
  const script: YumiScript = { seed: 40 + i, cues: [{ at: 0, habit }] };
  return (
    <div
      style={{
        position: "absolute",
        left: 120 + col * 450,
        top: 640 + row * 380,
        width: 390,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 14,
        opacity: Math.min(k, 1) * out,
        translate: `0 ${(1 - k) * 120}px`,
        scale: interpolate(k, [0, 1], [0.7, 1]),
      }}
    >
      <div style={{ position: "relative", width: 300, height: 252 }}>
        <Yumi
          script={script}
          size={300}
          style={{ position: "absolute", left: 0, top: 0 }}
        />
      </div>
      <div
        style={{
          fontFamily: THEME.text,
          fontSize: 42,
          fontWeight: 600,
          color: "#E4E6EE",
        }}
      >
        {label}
      </div>
    </div>
  );
};

export const CarouselMotion: React.FC<{ readonly lang: Lang }> = ({ lang }) => {
  const t = useT();
  const tx = TEXT[lang];

  // The big Yumi: in the middle until the habits, then he leaves upwards and comes back at the end
  const leave = interpolate(t, [HABITS_AT - 0.1, HABITS_AT + 0.5], [0, 1], {
    ...CLAMP,
    easing: EASE.in,
  });
  const back = interpolate(t, [END_AT, END_AT + 0.7], [0, 1], {
    ...CLAMP,
    easing: EASE.spring,
  });
  const lift = leave - back;
  // A slow push in while he changes, so the frame never stands still
  const push =
    interpolate(t, [0, HABITS_AT], [1, 1.08], CLAMP) *
    interpolate(back, [0, 1], [1, 0.82]);
  const endScript: YumiScript = {
    seed: 33,
    cues: [{ at: 0, mood: "happy", rim: "joy", habit: "headphones" }],
  };

  const skinBeats = SKINS.map((s, i) => {
    const at = COSTUMES_AT + 0.7 + i * STEP;
    return { text: s[lang], at, until: at + STEP - 0.12, n: i + 1 };
  });
  const moodBeats = MOODS.map((m, i) => {
    const at = MOODS_AT + 0.7 + i * (STEP + 0.08);
    return { text: m[lang], at, until: at + STEP - 0.04 };
  });

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      <Audio src={staticFile("musique/ambiance.wav")} volume={0.5} />

      {/* The big Yumi, through the intro, the costumes and the moods */}
      {t < END_AT ? (
        <AbsoluteFill
          style={{
            transformOrigin: `${BIG_X}px ${BIG_Y}px`,
            scale: push * interpolate(lift, [0, 1], [1, 0.2]),
            translate: `0 ${-lift * 900}px`,
            opacity: interpolate(lift, [0.7, 1], [1, 0], CLAMP),
          }}
        >
          <Yumi
            script={BIG}
            size={BIG_SIZE}
            style={{
              position: "absolute",
              left: BIG_X - BIG_SIZE / 2,
              top: BIG_Y - BIG_SIZE * 0.45,
            }}
          />
        </AbsoluteFill>
      ) : (
        <AbsoluteFill
          style={{
            transformOrigin: `${BIG_X}px ${BIG_Y}px`,
            translate: `0 ${interpolate(back, [0, 1], [-900, -120])}px`,
            scale: interpolate(back, [0, 1], [0.2, 0.78]),
          }}
        >
          <Yumi
            script={endScript}
            size={BIG_SIZE}
            style={{
              position: "absolute",
              left: BIG_X - BIG_SIZE / 2,
              top: BIG_Y - BIG_SIZE * 0.45,
            }}
          />
        </AbsoluteFill>
      )}

      {/* Intro */}
      <Kicker text={tx.kicker} at={0.5} until={COSTUMES_AT - 0.2} />
      <AbsoluteFill style={{ top: 1300 }}>
        <Words
          lines={[tx.intro]}
          enter={0.9}
          exit={COSTUMES_AT - 0.3}
          size={96}
          style={{ fontWeight: 700 }}
        />
      </AbsoluteFill>

      {/* Costumes */}
      <Kicker
        text={tx.costumes}
        at={COSTUMES_AT + 0.1}
        until={COSTUMES_END - 0.2}
      />
      {skinBeats.map((b) => (
        <React.Fragment key={b.text}>
          <Beat text={b.text} at={b.at} until={b.until} />
          <Beat
            text={tx.count(b.n)}
            at={b.at}
            until={b.until}
            size={40}
            color={THEME.muted}
            top={1430}
          />
        </React.Fragment>
      ))}

      {/* Moods */}
      <Kicker text={tx.moods} at={MOODS_AT + 0.1} until={MOODS_END - 0.2} />
      {moodBeats.map((b) => (
        <Beat key={b.text} text={b.text} at={b.at} until={b.until} />
      ))}

      {/* Habits */}
      <Kicker text={tx.habits} at={HABITS_AT + 0.2} until={HABITS_END - 0.3} />
      <AbsoluteFill style={{ top: 330 }}>
        <Words
          lines={tx.habitsTitle}
          enter={HABITS_AT + 0.25}
          exit={HABITS_END - 0.4}
          size={84}
          style={{ fontWeight: 700 }}
        />
      </AbsoluteFill>
      {t > HABITS_AT && t < HABITS_END + 0.1
        ? HABITS.map((h, i) => (
            <HabitSeat
              key={h.habit}
              habit={h.habit}
              label={h[lang]}
              i={i}
              lang={lang}
            />
          ))
        : null}

      {/* End */}
      <AbsoluteFill style={{ top: 1150 }}>
        <Words
          lines={tx.end}
          enter={END_AT + 0.4}
          size={120}
          style={{ fontWeight: 700 }}
        />
        <Words
          lines={[tx.endSub]}
          enter={END_AT + 0.9}
          size={44}
          style={{ fontWeight: 500, color: THEME.muted, marginTop: 28 }}
        />
      </AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 1620,
          display: "flex",
          justifyContent: "center",
          opacity: interpolate(t, [END_AT + 1.3, END_AT + 1.7], [0, 1], CLAMP),
          translate: `0 ${interpolate(t, [END_AT + 1.3, END_AT + 1.9], [30, 0], { ...CLAMP, easing: EASE.out })}px`,
        }}
      >
        <div
          style={{
            padding: "30px 64px",
            borderRadius: 999,
            background: THEME.fg,
            color: "#000",
            fontFamily: THEME.text,
            fontSize: 46,
            fontWeight: 700,
          }}
        >
          {tx.cta}
        </div>
      </div>

      {/* His sounds, on the beats */}
      <Son name="peek" at={0.35} />
      <Son name="greet" at={0.8} volume={0.6} />
      {skinBeats.map((b) => (
        <Son key={`s${b.n}`} name="pop" at={b.at} volume={0.45} />
      ))}
      {moodBeats.map((b, i) => (
        <Son
          key={`m${i}`}
          name={
            (["love", "question", "rate", "dizzy", "annoyed", "wink"] as const)[
              i
            ]
          }
          at={b.at}
          volume={0.45}
        />
      ))}
      {HABITS.map((h, i) => (
        <Son
          key={h.habit}
          name="blip"
          at={HABITS_AT + 0.6 + i * 0.28}
          volume={0.35}
        />
      ))}
      <Son name="proud" at={END_AT + 0.2} volume={0.6} />
    </AbsoluteFill>
  );
};
