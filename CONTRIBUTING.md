# Contributing to Yumi

Thanks for your interest. Yumi is a small project and moving fast, so please open an issue before starting anything large.

## Before you start

Read these two files first:

- [docs/journal.md](docs/journal.md): the decisions already taken (names, identifiers, character design). It wins over any other document.
- [docs/architecture.md](docs/architecture.md): the map of the code, folder by folder, and how a request travels through the app.

## Setup

You need macOS 15 or later, Xcode 16 or later and XcodeGen.

```bash
brew install xcodegen
```

```bash
cd Yumi && xcodegen && open Yumi.xcodeproj
```

The Xcode project and the `Info.plist` files are generated and ignored by git. To change a build setting, a target or a permission text, edit `Yumi/project.yml` and run `xcodegen` again. Never edit the generated files.

## Build and test

Run both before every commit:

```bash
cd Yumi && xcodegen && xcodebuild -scheme Yumi -configuration Debug build
```

```bash
cd Yumi && xcodebuild -scheme Yumi -configuration Debug test CODE_SIGNING_ALLOWED=NO
```

Continuous integration runs the same commands on every push, and also compiles the `YumiAppStore` target. That target is not shipped yet, but its `#if APPSTORE` blocks must keep compiling.

The Debug and App Store builds have no warning (Xcode 27). Keep it that way.

## Writing tests

Tests live in `Yumi/Tests/` and use Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`).

The test bundle is not hosted by the app. A file under test is compiled straight into the bundle, which is why running the tests never opens the island, never starts the hook server and never touches the Keychain. To test a new file:

1. Check that it depends on nothing else in the app (no `AppState`, no singleton).
2. Add its path to the `sources` of the `YumiTests` target in `Yumi/project.yml`.
3. Run `xcodegen`, then write the tests.

Most of the code reads and writes `AppState.shared` directly and cannot be tested this way yet. Pulling a pure piece of logic out of a large file so that it can be tested is a welcome contribution.

Timers: set a delay to a few hundredths of a second when the transition must happen, and to a very long value when it must not. See `IslandStateMachineTests.swift`.

## Rules

- Swift 6 with strict concurrency. SwiftUI and AppKit.
- No third-party dependency unless there is truly no other way.
- The character is drawn in code, by `Character/YumiRenderer.swift`, checked against `design/maquette/reference.html`.
- Never copy an icon, a sound, an image or a character design from another project. This repository is public.
- Secrets go in the Keychain. Never write a key to disk, to a log or to git.
- No telemetry. Network calls only to services the user configured.
- Never block Claude Code: if the app does not answer, the hook must exit at once.
- Never overwrite `~/.claude/settings.json`: dated backup, merge, preview, and write only after the user confirms.
- Never send an email or approve a Claude Code permission without an explicit click.
- Do not fix an odd behaviour in passing. Each one deserves its own change, with its own description.

## Teaching Yumi a new trick

Each action Yumi can take is one tool in `Yumi/Sources/App/AgentRuntime/Tools/`, following the `Tool` protocol (`AgentRuntime/Tool.swift`). Start from the closest existing one (`AddReminderTool.swift` is a good model):

1. **`descriptor`**: id, name, description, input schema and risk. The planner only sees this.
2. **`action(for:)`**: what the tool really touches (read, create, modify, and which resource). The permission manager computes the risk from it; refuse what the tool was not made for.
3. **`check`**: what can be checked before asking the person (a missing access, a bad argument).
4. **`execute`**: does the thing.
5. **`verify`**: looks again and returns a message if the result is not really there.

Register it in `App/AppDelegate.swift`, next to the other tools, and add tests in `Yumi/Tests/AgentRuntime/` (see `AgentToolsTests.swift` and `WriteToolsRefusalTests.swift`). A tool never asks the person itself and never bypasses the permission manager.

Ideas waiting for someone are labelled `new trick` in the issues.

## Proposing a change

1. Create a branch from `main`. Nobody pushes to `main` directly.
2. Keep the change focused: one subject per pull request.
3. Build and run the tests.
4. If the change is visible, try it by hand: launch and greeting, hover, click, the three tabs, Claude Code hooks and approvals, file drop, chat, sounds, shortcut.
5. Open a pull request that says what changes for the user and how you checked it.

## Reporting a bug

Open an issue with your macOS version, your Mac model (with or without a notch), what you did, what you expected and what happened. For a problem with Claude Code, the log in `~/Library/Logs/Yumi/` helps. Check that it holds nothing private before attaching it.

Please do not report a security problem in a public issue. Write to the maintainer first.

## Releases

Releases are made by the maintainer by pushing a tag `v<version>` that matches `YumiDisplayVersion` in `Yumi/project.yml`. The [release workflow](.github/workflows/release.yml) then runs on GitHub's machines: it tests, builds the Release configuration, signs it with the « Yumi Local » certificate (stored in the repository secrets), zips it with the install guides, publishes `SHA256SUMS.txt` and a build provenance attestation, and opens a draft pre-release that the maintainer reviews and publishes by hand. The builds are not notarized by Apple.

`scripts/release.sh` is the notarized path (Developer ID certificate and an Apple Developer account). It is not used today, since there is no Apple Developer account yet. Do not run either in a pull request.

## License

By contributing, you agree that your contribution is published under the [MIT License](LICENSE). The Yumi name, character, icons and sounds are not covered by that license.
