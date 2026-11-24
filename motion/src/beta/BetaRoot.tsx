import "../index.css";
import { Composition } from "remotion";
import { BETA_LENGTH, Beta } from "./Beta";

export const BetaRoot: React.FC = () => (
  <>
    <Composition id="Beta-Animation" component={Beta} durationInFrames={Math.round(BETA_LENGTH * 60)} fps={60} width={1080} height={1920} defaultProps={{ reel: false, filmed: false }} />
    <Composition id="Beta-PlanFilme" component={Beta} durationInFrames={Math.round(BETA_LENGTH * 60)} fps={60} width={1080} height={1920} defaultProps={{ reel: true, filmed: false }} />
  </>
);
