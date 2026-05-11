# XcodeBuildMCP Workshop — Q&A Prep

For Sergiy-hosted workshop, ~60 min. Sergiy will ask questions live as we go.
Answers below are talking-point beats, not scripts — keep delivery conversational.

---

## Act 1 — Setup & install

**Q: What does `xcodebuildmcp setup` actually do?**
- Walks the project, detects targets/schemes/workspaces, writes a project-local config under `.xcodebuildmcp/`.
- Picks workflows (simulator-only vs ui-automation vs full-device) — workflows gate which tools are exposed to the agent, which keeps the tool surface small and the agent focused.
- "Session defaults" lets us pin scheme / destination / sim once so every subsequent tool call stays consistent without re-prompting.

**Q: Why does this need to be project-aware? Doesn't an MCP just expose generic tools?**
- Most coding agents waste tokens rediscovering the build graph every session. We do it once at setup time and persist it.
- The agent calls `simulator build-and-run` instead of inventing an `xcodebuild ...` invocation each time. That's where the deterministic API surface comes from.

**Q: What does `xcodebuildmcp init` install?**
- Skills — short instruction files dropped into the agent's context that teach it *how* to use the tools, not just that they exist. Examples: when to take a screenshot, how to chain build-and-run, how to use LLDB tools.
- Without skills, the agent has tools but no idiom. With them, it picks the right one first try.

**Q: Does it work with SwiftPM packages? Workspaces? Tuist/XcodeGen?**
- Yes to .xcodeproj and .xcworkspace, yes to SwiftPM. Tuist/XcodeGen produce standard Xcode projects so they work too — you just regenerate as normal.
- macOS, watchOS, tvOS, visionOS targets all supported.

**Q: Which editors are supported?**
- Anything that speaks MCP. Today that's Claude Code, Cursor, VS Code (via Copilot/Cline), Codex, Windsurf. Setup command writes the right config for each.

---

## Act 2 — Build, run, fix

**Q: How does the agent know how to read a build error?**
- Tool returns structured output: file, line, column, severity, message — already parsed from xcodebuild's xcresult bundle. The agent doesn't grep through 5,000 lines of warnings.
- That's part of the "~⅓ fewer tokens" claim: the expensive part is the agent generating output, and we strip the noise before it has to think about it.

**Q: Why is this better than the agent just running `xcodebuild` itself?**
- It can — but xcodebuild's output is verbose, locale-dependent, and inconsistent across Xcode versions. Agents spend tokens parsing it and hallucinate paths that don't exist. We do the parsing in TypeScript code that sees the same shape every time.
- Also: build settings, codesigning, scheme resolution, simulator picking — all the stuff that's a footgun if the agent invents flags.

**Q: What about codesigning, provisioning, schemes with funky configurations?**
- We expose `show_build_settings` to surface what Xcode resolved, so the agent reasons over actual values, not guesses.
- For local sim demos like today, codesigning is automatic; for device/CI we expose the right knobs but keep them explicit.

**Q: Long build outputs — doesn't that blow up the agent's context?**
- Output is filtered to errors + warnings by default. Full logs are written to disk and exposed via a path the agent can grep on demand. The agent only pulls what it needs.

---

## Act 3 — UI automation & verification

**Q: How does the agent "see" the screen?**
- Two modes. Screenshots (`screenshot` tool) — pixel image the agent reads visually. UI snapshot (`snapshot_ui`) — accessibility tree as structured text, which is faster and cheaper for "find the button labelled X" type tasks.
- Best demo move: use snapshot_ui to navigate, screenshot to verify the result looks right.

**Q: Is it OCR? Accessibility tree? Both?**
- Accessibility tree primarily — that's what XCUITest uses under the hood. Screenshots are passed to the multimodal model when visual layout matters. No OCR.
- This is why our app uses `accessibilityIdentifier` everywhere — makes the agent's life easier.

**Q: Can it handle gestures, scrolling, dynamic content?**
- Tap, type, swipe, scroll, long-press, key input — all in. Animations are a fact of life; we expose `record_sim_video` if you want to debug something time-based.

**Q: Why didn't the agent catch the dead `alertsEnabled` toggle from reading code?**
- It could have, on a careful read. But the demo point is: when asked to make a Settings toggle "do something", the agent's first move should be to *test* the app — open Settings, flip the switch, see what changes — not just stare at the source and guess. That's the loop we want: code + test + verify, not code + assume.

**Q: Does it work on real devices?**
- Yes — physical iOS devices via `devicectl` under the hood. Simulator is faster for iteration, device for actual hardware-dependent things (camera, sensors, push).

---

## Act 4 — LLDB / runtime debugging

**Q: Wait, the agent is driving LLDB? How?**
- Yep. We spawn an LLDB session, attach to the running app, and expose set-breakpoint, continue, step, and inspect-variables as MCP tools. The agent uses them like any other tool.
- The model never sees raw lldb output it has to parse — we structure it.

**Q: Why is this necessary when you've got Sentry / logging?**
- Sentry tells you something went wrong in production. LLDB tells you *what the variables actually were* on a development machine. Different stages of the loop.
- The bug we just hit — wind direction `0` from a backend that uses 0 to mean north, tripping the iOS model's `1...360` precondition — looks defensible on either side in isolation. You only catch a cross-system contract mismatch like this by stepping into the running app with real data flowing through it.

**Q: Conditional breakpoints, memory inspection, watchpoints?**
- Conditional breakpoints yes. Frame variable / expression evaluation yes. Watchpoints are on the roadmap.

**Q: Performance overhead?**
- Same as a normal Xcode debugging session — LLDB is the same LLDB. We're not running a profiler.

**Q: Can it attach to an already-running app, or does it have to launch?**
- Both. Launch with `build_run_sim` for fresh state, attach with `attach` for an app already running.

---

## Act 5 — Sentry integration

**Q: Why integrate Sentry if you've got LLDB?**
- LLDB is for the developer machine. Sentry is for everywhere else — TestFlight, prod, every user's device. The agent gets the same structured error context whether the bug repro'd locally or in the field.
- Plus the distributed-trace story we just showed: client-side error linked to a backend exception in one click. LLDB can't do that.

**Q: How does the agent actually use Sentry context?**
- Via the Sentry MCP. It reads issues, fingerprints, breadcrumbs, traces — and uses that as input to its plan. So instead of "fix this crash", it's "fix this crash, given this stack frame, these breadcrumbs, and this distributed trace from the backend".

**Q: What's the Sentry MCP and how does it differ from XcodeBuildMCP?**
- Two complementary MCPs, two surfaces. Sentry MCP exposes your Sentry org — issues, traces, releases. XcodeBuildMCP exposes your Apple toolchain — build, run, debug, automate. The agent uses both in the same session.

**Q: dSYM / source map upload — does the agent handle that?**
- Sentry's Xcode build phase script handles dSYM upload at build time, same as any human workflow. Sentry-wizard sets it up. The agent doesn't need to do anything special.

**Q: Now that XcodeBuildMCP is part of Sentry, what changes?**
- Tool stays open source, MIT-licensed. Roadmap continues. Tighter Sentry integration over time, but no lock-in — the goal is still "best-in-class iOS agentic dev tool", and that means it has to work standalone too.
- Personally: now I get to work on this full-time, which is why we can ship faster.

---

## General / cross-cutting

**Q: How is this different from Xcode 26's built-in AI?**
- Xcode's AI lives inside Xcode. XcodeBuildMCP makes any agent — Cursor, Claude Code, your own — first-class on Apple platforms, in your editor of choice, with a deterministic tool surface. Not competitive; complementary. Use both.

**Q: vs Cursor / Claude Code natively without an MCP?**
- They can shell out to xcodebuild — but every session they re-discover the project, re-parse error output, re-guess flags. Token-expensive and brittle. We pay that cost once at setup time.
- Concrete number: ~⅓ fewer output tokens on equivalent tasks. Output tokens are the expensive ones.

**Q: Hallucinations — what stops the agent from inventing symbols?**
- Tools that return real data instead of letting the model freelance. `list_schemes` is a real list, not a guess. `show_build_settings` is the real resolved value. Less surface for hallucination = fewer hallucinations.
- Skills also constrain behavior — telling the agent "use this tool first" reduces the cases where it improvises.

**Q: Privacy — does my code leave the machine?**
- XcodeBuildMCP itself is local — runs on your machine, talks to the local agent. Whatever your editor / model provider does is between you and them. Same privacy posture as your editor.

**Q: What models work with this?**
- Anything that supports tool use via MCP. Claude Sonnet/Opus, GPT-4/5, Gemini, local models with MCP support. We don't ship our own model.

**Q: Token cost?**
- Hard to give a single number — varies by task. The headline is ~⅓ fewer output tokens for the same outcome vs unaided agent. Bigger projects, bigger savings.

**Q: Concurrent agents on the same project?**
- Supported. Filesystem state under `~/Library/Developer/XcodeBuildMCP` is multi-process safe — workspace-keyed dirs, locking on shared files.

**Q: React Native / Flutter / Capacitor?**
- The native iOS half — yes, anything that produces an .xcodeproj. The cross-platform JS/Dart side is outside our scope.

**Q: Open source, license, contributions?**
- MIT, on GitHub at getsentry/XcodeBuildMCP (recent transition). Issues + PRs welcome.

---

## Curveballs / harder questions

**Q: Won't this make junior engineers worse?**
- Same answer as any tool that automates the tedious bits. The senior skill — knowing what to build and what's worth debugging — still matters. The drudge skill — remembering 30 xcodebuild flags — matters less, and that's fine.

**Q: What if the agent fixes a bug by introducing another?**
- Same as any code change — you read the diff, run the tests, ship it. UI automation actually closes part of that loop because the agent can verify visually before declaring done. "Fixed and screenshot looks right" is a stronger claim than "fixed".

**Q: How often does it actually work end-to-end without intervention?**
- Honest answer: depends heavily on task complexity and model. For the build/run/test/screenshot loop on a project this size, very high. For "implement an entire feature from spec", we're still in human-in-the-loop territory. The tool's job is to make every step of that loop cheaper, not to remove the human.

**Q: Apple's stance? Are you stepping on their toes?**
- We use public Apple toolchain — xcodebuild, simctl, devicectl, lldb. No private API. Apple ships AI in Xcode; we make agents work outside Xcode. Two different bets on the same future.

**Q: "Isn't this just a wrapper around xcodebuild?"**
- It wraps xcodebuild + simctl + devicectl + lldb + xcresult parsing + workflow management + skill provisioning. The wrapping is the product — that's what makes the agent reliable instead of frustrating.

---

## Things I want Sergiy to ask me

(Plant these with him beforehand if possible.)

- "Show me the logs the agent saw when it figured out the precipitation bug."
- "What did the build error output look like before the agent fixed it?"
- "Open the Sentry trace and walk us through what the agent reads."
- "How long would this same loop take you in plain Xcode?"
- "Why did you pick MCP over building a Sentry-specific Cursor extension?"
