import React from "react";
import { Audio, Video } from "@remotion/media";
import { AbsoluteFill, Sequence, interpolate, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { EASE } from "../theme";
import { Words } from "../type/Words";
import { Fin } from "../scenes/Fin";
import durees from "./voix-durees.json";

// The film of the new island (design/video-beta.md): every module, what it is for, told by
// Yumi's own voice. The takes are the real island in filming mode, at its real size
// (YUMI_ISLAND_V2_SHOTS with YUMI_ISLAND_V2_HOLD=5, public/prises/beta/ile-modules.mp4):
// after the launch, each page of the island stays 5 s, one after the other.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;
const ramp = (t: number, a: number, b: number, ease = EASE.camera) => interpolate(t, [a, b], [0, 1], { ...CLAMP, easing: ease });

/** When the first page of the island shows in the take, and how long each stays. */
const FIRST = 7.0;
const EACH = 6.2;
/** The part of a page worth showing: after it settled, before the next one. */
const page = (i: number, length = 4.6) => ({ at: FIRST + i * EACH + 1.4, length });

/** One idea per part: a title, the pieces of the take that show it. */
const PARTS: readonly { title: string; pieces: readonly { at: number; length: number }[] }[] = [
  { title: "Il se réveille.", pieces: [{ at: 0.4, length: 6.4 }] },
  { title: "Survole-le, il s'ouvre.", pieces: [page(0), page(1), page(2)] },
  { title: "Ta journée, ta musique.", pieces: [page(3), page(4), page(5)] },
  { title: "Tes agents.", pieces: [page(6)] },
  { title: "La météo, pour de vrai.", pieces: [page(8, 2.4), page(10, 2.4), page(12, 2.4)] },
  { title: "Agenda et concentration.", pieces: [page(13), page(15)] },
  { title: "GitHub et Gmail.", pieces: [page(16), page(17)] },
  { title: "Tu autorises. Ou pas.", pieces: [page(18)] },
  { title: "Écris-lui, parle-lui.", pieces: [page(19), page(20), page(21)] },
  { title: "Dépose un fichier.", pieces: [page(22), page(23), page(24)] },
  { title: "Et il a du style.", pieces: [page(25), page(26)] },
];

const GAP = 0.5;
const lengths = PARTS.map((_, i) => (durees.mac[i] ?? 6) + GAP);
const END = Math.max(3.3, (durees.mac[PARTS.length] ?? 3.3) + 0.6);
const total = lengths.reduce((a, b) => a + b, 0);
export const ILE_LENGTH = total + END;

/** The island on the top of a MacBook screen, filmed close. */
const Screen: React.FC<{ readonly part: number; readonly t: number; readonly length: number; readonly wide: boolean }> = ({ part, t, length, wide }) => {
  const { fps } = useVideoConfig();
  const pieces = PARTS[part].pieces;
  // The part's time, shared between its pieces
  const share = length / pieces.length;
  const k = Math.min(pieces.length - 1, Math.floor(t / share));
  const piece = pieces[k];
  const rate = Math.min(1.6, Math.max(0.6, piece.length / share));
  const w = wide ? 1500 : 1400;
  return (
    <div style={{ position: "absolute", left: "50%", top: wide ? 120 : 330, width: w, height: w * (1000 / 2200), transform: "translateX(-50%)" }}>
      {/* The screen's top edge and its notch: the island hangs from it */}
      <div style={{ position: "absolute", inset: 0, borderRadius: 26, overflow: "hidden", background: "#000", boxShadow: "0 0 0 10px #1b1b1f, 0 60px 160px rgba(0,0,0,0.8)" }}>
        <Sequence key={`${part}-${k}`} from={Math.round(k * share * fps)} layout="none">
          <Video src={staticFile("prises/beta/ile-modules.mp4")} muted trimBefore={Math.round(piece.at * fps)} playbackRate={rate} style={{ width: "100%", height: "100%", objectFit: "cover" }} />
        </Sequence>
      </div>
    </div>
  );
};

export const Ile: React.FC<{ readonly voice?: boolean }> = ({ voice = false }) => {
  const { fps, width: VW, height: VH } = useVideoConfig();
  const t = useCurrentFrame() / fps;
  const wide = VW > VH;
  let start = 0;
  let part = -1;
  for (let i = 0; i < PARTS.length; i++) {
    if (t < start + lengths[i]) {
      part = i;
      break;
    }
    start += lengths[i];
  }
  const pt = t - start;
  const fade = part >= 0 ? ramp(pt, 0, 0.35) * (1 - ramp(pt, lengths[part] - 0.3, lengths[part])) : 0;

  return (
    <AbsoluteFill style={{ background: "#050507" }}>
      {/* A slow light behind the screen, the only movement of the room */}
      <AbsoluteFill style={{ background: `radial-gradient(60% 40% at 50% ${wide ? 30 : 25}%, rgba(91,140,255,${0.08 + 0.03 * Math.sin(t * 0.4)}), transparent 70%)` }} />
      {part >= 0 ? (
        <>
          <AbsoluteFill style={{ opacity: 0.35 + 0.65 * fade }}>
            <Sequence from={Math.round(start * fps)} layout="none">
              <Screen part={part} t={pt} length={lengths[part]} wide={wide} />
            </Sequence>
          </AbsoluteFill>
          <AbsoluteFill style={{ top: wide ? VH * 0.78 : VH * 0.72 }}>
            <Sequence key={part} from={Math.round(start * fps)} durationInFrames={Math.round(lengths[part] * fps)} layout="none">
              <Words lines={[PARTS[part].title]} enter={0.3} exit={lengths[part] - 0.7} size={wide ? 64 : 72} />
            </Sequence>
          </AbsoluteFill>
        </>
      ) : null}

      <Sequence from={Math.round(total * fps)} layout="none">
        <Fin subtitle="La nouvelle île. Bêta gratuite." />
      </Sequence>

      {voice
        ? PARTS.map((_, i) => {
            const at = lengths.slice(0, i).reduce((a, b) => a + b, 0);
            return (
              <Sequence key={i} from={Math.round((at + 0.25) * fps)} layout="none">
                <Audio src={staticFile(`voix/mac-${i}.mp3`)} />
              </Sequence>
            );
          })
        : null}
      {voice ? (
        <Sequence from={Math.round((total + 0.3) * fps)} layout="none">
          <Audio src={staticFile(`voix/mac-${PARTS.length}.mp3`)} />
        </Sequence>
      ) : null}
    </AbsoluteFill>
  );
};
