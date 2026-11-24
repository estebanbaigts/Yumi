import { registerRoot } from "remotion";
import { BetaRoot } from "./BetaRoot";

// The film of the beta has its own entry: `npx remotion studio src/beta/index.ts`.
registerRoot(BetaRoot);
