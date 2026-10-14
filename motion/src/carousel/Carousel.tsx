import React from "react";
import { AbsoluteFill } from "remotion";
import { THEME } from "../theme";
import { Yumi } from "../yumi/Yumi";
import type { Habit } from "../yumi/blob";
import type { Cue, YumiScript } from "../yumi/engine";
import type { Mood, RimTone } from "../yumi/faces";
import type { SkinName } from "../yumi/skins";

// An Instagram carousel (1080 × 1350): his costumes, his moods, his habits, drawn by the
// same code as the app's character. Each slide is a still taken `AT` seconds in, once every
// habit has started its routine. In French and in English.

export type Lang = "fr" | "en";

/** The frame each slide is rendered at, in seconds: the habits are all under way by then. */
export const CAROUSEL_AT = 2.6;

type Cell = { readonly label: string; readonly cues: readonly Cue[] };

const cell = (label: string, cues: readonly Cue[]): Cell => ({ label, cues });
const skin = (label: string, name: SkinName, mood: Mood = "happy"): Cell =>
  cell(label, [{ at: 0, skin: name, mood }]);
const mood = (label: string, name: Mood, rim?: RimTone): Cell =>
  cell(label, [{ at: 0, mood: name, rim }]);
const habit = (label: string, name: Habit): Cell =>
  cell(label, [{ at: 0.2, habit: name }]);

type Slide = {
  readonly kicker: string;
  readonly title: string;
  readonly sub?: string;
  readonly cells: readonly Cell[];
  readonly big?: boolean;
  readonly cta?: string;
};

const SLIDES: Record<Lang, readonly Slide[]> = {
  fr: [
    {
      kicker: "YUMI · ALPHA 10",
      title: "Il a du caractère.",
      sub: "Ses costumes, ses humeurs, ses petites habitudes.",
      cells: [
        cell("", [
          { at: 0, mood: "happy", rim: "joy", skin: "aureole" },
          { at: 1.2, mood: "wink" },
        ]),
      ],
      big: true,
    },
    {
      kicker: "1 · SES COSTUMES",
      title: "Habille-le.",
      cells: [
        skin("Le bonnet", "bonnet"),
        skin("L'auréole", "aureole"),
        skin("Les cornes", "cornes", "wink"),
        skin("Les lunettes", "lunettes"),
      ],
    },
    {
      kicker: "1 · SES COSTUMES",
      title: "Huit en tout.",
      cells: [
        skin("La pousse", "pousse"),
        skin("La casquette", "casquette", "curious"),
        skin("Le nœud pap'", "noeud"),
        skin("La moustache", "moustache", "wink"),
      ],
    },
    {
      kicker: "2 · SES HUMEURS",
      title: "Il réagit.",
      cells: [
        mood("Content", "happy", "joy"),
        mood("Curieux", "curious", "think"),
        mood("Surpris", "surprised", "warn"),
        mood("Inquiet", "worried", "warn"),
        mood("Agacé", "annoyed", "error"),
        mood("Complice", "wink", "calm"),
      ],
    },
    {
      kicker: "3 · SES HABITUDES",
      title: "Pendant qu'un agent bosse.",
      cells: [
        habit("Un café", "coffee"),
        habit("Un matcha", "matcha"),
        habit("Sa musique", "headphones"),
        habit("Les lunettes", "sunglasses"),
        habit("Un nuage", "cloud"),
        habit("Une sieste", "sleep"),
      ],
    },
    {
      kicker: "YUMI · ALPHA 10",
      title: "Gratuit, pour Mac.",
      sub: "Sans compte. Tout reste sur ton Mac.",
      cells: [
        cell("", [{ at: 0, mood: "happy", rim: "joy", habit: "headphones" }]),
      ],
      big: true,
      cta: "Lien en bio",
    },
  ],
  en: [
    {
      kicker: "YUMI · ALPHA 10",
      title: "He has character.",
      sub: "His costumes, his moods, his little habits.",
      cells: [
        cell("", [
          { at: 0, mood: "happy", rim: "joy", skin: "aureole" },
          { at: 1.2, mood: "wink" },
        ]),
      ],
      big: true,
    },
    {
      kicker: "1 · COSTUMES",
      title: "Dress him up.",
      cells: [
        skin("The beanie", "bonnet"),
        skin("The halo", "aureole"),
        skin("The horns", "cornes", "wink"),
        skin("The glasses", "lunettes"),
      ],
    },
    {
      kicker: "1 · COSTUMES",
      title: "Eight of them.",
      cells: [
        skin("The sprout", "pousse"),
        skin("The cap", "casquette", "curious"),
        skin("The bow tie", "noeud"),
        skin("The moustache", "moustache", "wink"),
      ],
    },
    {
      kicker: "2 · MOODS",
      title: "He reacts.",
      cells: [
        mood("Happy", "happy", "joy"),
        mood("Curious", "curious", "think"),
        mood("Surprised", "surprised", "warn"),
        mood("Worried", "worried", "warn"),
        mood("Annoyed", "annoyed", "error"),
        mood("Cheeky", "wink", "calm"),
      ],
    },
    {
      kicker: "3 · HABITS",
      title: "While an agent works.",
      cells: [
        habit("A coffee", "coffee"),
        habit("A matcha", "matcha"),
        habit("His music", "headphones"),
        habit("Shades on", "sunglasses"),
        habit("A cloud", "cloud"),
        habit("A nap", "sleep"),
      ],
    },
    {
      kicker: "YUMI · ALPHA 10",
      title: "Free, for Mac.",
      sub: "No account. Everything stays on your Mac.",
      cells: [
        cell("", [{ at: 0, mood: "happy", rim: "joy", habit: "headphones" }]),
      ],
      big: true,
      cta: "Link in bio",
    },
  ],
};

export const CAROUSEL_SLIDES = SLIDES.fr.length;

const W = 1080;
const H = 1350;

const Figure: React.FC<{
  readonly cues: readonly Cue[];
  readonly size: number;
  readonly seed: number;
}> = ({ cues, size, seed }) => {
  const script: YumiScript = { seed, cues };
  return (
    <div style={{ position: "relative", width: size, height: size * 0.84 }}>
      <Yumi
        script={script}
        size={size}
        style={{ position: "absolute", left: 0, top: 0 }}
      />
    </div>
  );
};

export const CarouselSlide: React.FC<{
  readonly lang: Lang;
  readonly index: number;
}> = ({ lang, index }) => {
  const slide = SLIDES[lang][index];
  const count = SLIDES[lang].length;
  const columns = slide.cells.length > 4 ? 3 : 2;
  const size = slide.big ? 620 : columns === 3 ? 250 : 340;
  return (
    <AbsoluteFill
      style={{
        width: W,
        height: H,
        backgroundColor: THEME.black,
        fontFamily: THEME.text,
        color: THEME.fg,
        alignItems: "center",
        padding: "110px 70px 90px",
        boxSizing: "border-box",
      }}
    >
      <div
        style={{
          fontSize: 28,
          fontWeight: 700,
          letterSpacing: "0.3em",
          color: "#B9A6FF",
        }}
      >
        {slide.kicker}
      </div>
      <div
        style={{
          fontSize: slide.big ? 104 : 84,
          fontWeight: 700,
          letterSpacing: "-0.025em",
          marginTop: 26,
          textAlign: "center",
          lineHeight: 1.05,
        }}
      >
        {slide.title}
      </div>
      {slide.sub ? (
        <div
          style={{
            fontSize: 38,
            fontWeight: 500,
            color: THEME.muted,
            marginTop: 22,
            textAlign: "center",
            maxWidth: 860,
            lineHeight: 1.3,
          }}
        >
          {slide.sub}
        </div>
      ) : null}

      <div
        style={{
          flex: 1,
          width: "100%",
          display: "grid",
          gridTemplateColumns: `repeat(${slide.big ? 1 : columns}, minmax(0, 1fr))`,
          alignContent: "center",
          justifyItems: "center",
          rowGap: columns === 3 ? 40 : 56,
        }}
      >
        {slide.cells.map((c, i) => (
          <div
            key={c.label + i}
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              gap: 18,
            }}
          >
            <Figure cues={c.cues} size={size} seed={index * 10 + i + 1} />
            {c.label ? (
              <div
                style={{
                  fontSize: columns === 3 ? 34 : 38,
                  fontWeight: 600,
                  color: "#E4E6EE",
                }}
              >
                {c.label}
              </div>
            ) : null}
          </div>
        ))}
      </div>

      {slide.cta ? (
        <div
          style={{
            padding: "26px 58px",
            borderRadius: 999,
            background: THEME.fg,
            color: "#000",
            fontSize: 42,
            fontWeight: 700,
            marginBottom: 34,
          }}
        >
          {slide.cta}
        </div>
      ) : null}

      {/* Where we are in the carousel, and a nudge to swipe on all but the last */}
      <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
        {Array.from({ length: count }, (_, i) => (
          <div
            key={i}
            style={{
              width: i === index ? 34 : 12,
              height: 12,
              borderRadius: 6,
              background: i === index ? THEME.fg : "#3A3D4C",
            }}
          />
        ))}
      </div>
    </AbsoluteFill>
  );
};
