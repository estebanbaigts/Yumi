import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { EASE, THEME } from "../theme";
import { Son } from "../son/Son";
import { Words } from "../type/Words";
import { Yumi } from "../yumi/Yumi";
import type { YumiScript } from "../yumi/engine";
import { CLOSE, EYES, SIZE, YUMI_AT } from "./stage";

// The end (design/yumi/video.md, 20 to 22 s). Him in his light, a wink. « Yumi. Bientôt. »
//
// Then he does what he does when the app quits: he falls asleep and his light goes out,
// while the camera closes in on his eyes. The last image is the first one of the hook,
// two sleeping eyes in the dark, so the film loops without a seam.

const CLAMP = { extrapolateLeft: "clamp", extrapolateRight: "clamp" } as const;

/** When he starts to fall asleep, in seconds. */
const NIGHT = 2.3;
/** Length of the shot: the composition must last exactly this long for the loop to join. */
const LENGTH = 3.3;
/** One breath of Yumi awake (he breathes as sin(1.5 t)). */
const BREATH = (2 * Math.PI) / 1.5;

const SCRIPT: YumiScript = {
  seed: 21,
  // He ends his last breath where the hook starts its first
  breath: BREATH - (LENGTH % BREATH),
  cues: [
    { at: 0, mood: "happy", rim: "joy", pose: "boing" },
    { at: 0.95, mood: "wink", rim: "calm" },
    { at: 1.55, mood: "happy" },
    { at: NIGHT, mood: "asleep", pose: "dip" },
    { at: NIGHT + 0.35, lit: false },
  ],
};

export const Fin: React.FC<{ readonly subtitle?: string }> = ({ subtitle = "Bientôt." }) => {
  const { fps } = useVideoConfig();
  const t = useCurrentFrame() / fps;

  return (
    <AbsoluteFill style={{ backgroundColor: THEME.black }}>
      {/* Camera: still while the name is read, then in on the eyes as the light goes out */}
      <AbsoluteFill
        style={{
          transformOrigin: `${EYES.x}px ${EYES.y}px`,
          scale: interpolate(t, [NIGHT, NIGHT + 0.95], [1, CLOSE], { ...CLAMP, easing: EASE.camera }),
        }}
      >
        <Yumi script={SCRIPT} size={SIZE} style={YUMI_AT} />
      </AbsoluteFill>

      <AbsoluteFill style={{ top: 1230 }}>
        <Words lines={["Yumi."]} by="letter" enter={0.2} exit={NIGHT - 0.25} size={210} style={{ fontWeight: 700 }} />
        <Words
          lines={[subtitle]}
          enter={0.55}
          exit={NIGHT - 0.15}
          size={64}
          style={{ fontWeight: 500, color: THEME.muted, marginTop: 18 }}
        />
      </AbsoluteFill>

      <Son name="proud" at={0.05} />
      <Son name="wink" at={1.0} />
      <Son name="yawn" at={NIGHT} />
      <Son name="close" at={NIGHT + 0.35} volume={0.6} />
    </AbsoluteFill>
  );
};
