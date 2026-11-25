import "../index.css";
import { Composition } from "remotion";
import { BETA_LENGTH, Beta } from "./Beta";
import { ILE_LENGTH, Ile } from "./Ile";

const frames = Math.round(BETA_LENGTH * 60);

export const BetaRoot: React.FC = () => (
  <>
    <Composition id="Beta-Vertical" component={Beta} durationInFrames={frames} fps={60} width={1080} height={1920} defaultProps={{ reel: false, filmed: false }} />
    <Composition id="Beta-Ordinateur" component={Beta} durationInFrames={frames} fps={60} width={1920} height={1080} defaultProps={{ reel: false, filmed: false }} />
    <Composition id="Beta-PlanFilme-Vertical" component={Beta} durationInFrames={frames} fps={60} width={1080} height={1920} defaultProps={{ reel: true, filmed: false }} />
    <Composition id="Beta-PlanFilme-Ordinateur" component={Beta} durationInFrames={frames} fps={60} width={1920} height={1080} defaultProps={{ reel: true, filmed: false }} />
    <Composition id="Ile-Vertical" component={Ile} durationInFrames={Math.round(ILE_LENGTH * 60)} fps={60} width={1080} height={1920} defaultProps={{ voice: false }} />
    <Composition id="Ile-Ordinateur" component={Ile} durationInFrames={Math.round(ILE_LENGTH * 60)} fps={60} width={1920} height={1080} defaultProps={{ voice: false }} />
  </>
);
