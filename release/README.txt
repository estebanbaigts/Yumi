YUMI, {{VERSION}}
A small companion that lives in your Mac's notch.

Thanks for trying Yumi. This is an alpha: it is not notarized by Apple yet,
hence step 3 below, which you only do once.


YOU NEED

- A Mac running macOS 15 or later (ideally one with a notch).
- Nothing else to start: no account, no subscription. The chat works from
  the first launch, with Apple's model (macOS 26 and Apple Intelligence) or,
  on any Mac, in simple mode.
- Later, if you want a bigger engine (Settings > Engines): Claude Code, an
  Anthropic, OpenAI or Google Gemini key (billed by the provider; Gemini has
  a free tier), or Ollama running locally (free).
- To follow your coding agents (Claude Code, Codex, Gemini CLI): python3
  (from Homebrew, python.org, or Apple's command line tools).


INSTALL

1. Drag Yumi.app into your Applications folder.

2. Open it (double-click). macOS says "Yumi cannot be opened":
   click Done, that is expected for an alpha.

3. Open System Settings > Privacy & Security.
   At the bottom, next to "Yumi was blocked", click "Open Anyway",
   then confirm with your password.

4. Yumi appears in the notch. Done: next time it opens normally.

Yumi asks for your calendar, reminders or location only when you use the
module that needs it. You can refuse everything: each access only unlocks
one feature.


FOLLOW CLAUDE CODE (optional)

In Yumi's settings (menu bar icon), install the Claude Code hooks. Yumi
shows the change before writing it, keeps a copy of your settings file, and
refuses to touch it if it is damaged.


LANGUAGE

Yumi speaks English and French. It follows your Mac's language; change it
in Settings > General > Language.


YOUR PRIVACY

No account, no ads, no telemetry. Your calendar, your reminders and what
Yumi remembers about you stay on your Mac. Yumi never does anything that
changes your Mac without asking you first in the notch.


A BUG, AN IDEA?

Yumi's settings > "Send feedback". It opens a GitHub form with your Yumi
and macOS versions already filled in. Yumi tells you when a new version is
out.


KNOWN LIMITS

- Not tested yet on a Mac without a notch.
- OpenAI, Gemini and Ollama are new: tell me if they work for you.


CHECK THIS ZIP (optional)

This zip is built by GitHub Actions from the public code of the repository,
not on the author's computer. To check it was not modified:

  shasum -a 256 Yumi-{{VERSION}}.zip

must match the sum in SHA256SUMS.txt, on the release page. With GitHub's
gh tool, you can also check where it comes from:

  gh attestation verify Yumi-{{VERSION}}.zip --repo estebanbaigts/Yumi


UNINSTALL

If you installed the hooks, remove them first from Yumi's settings. Then
quit Yumi and move Yumi.app to the Trash.
