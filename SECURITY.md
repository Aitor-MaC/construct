# Security policy

A terminal sees everything you type, so security reports are very welcome.

## Reporting a vulnerability

Please **don't open a public issue**. Use GitHub's private reporting instead: go to the repository's **Security** tab and choose **Report a vulnerability**. Include the Construct version (Construct ▸ About Construct), your macOS version and the steps to reproduce.

You'll get an answer as soon as possible. Once a fix is released, the report can be made public with credit to you, if you want.

## Supported versions

Only the latest release receives security fixes.

## What Construct does to protect you

- **Shell integration messages are signed.** Command marks, the working directory and AI requests travel as OSC 7777 messages with a per-session nonce that is never exported to child processes. Text printed by a program (`cat`, `ssh`, a malicious file) can't fake them.
- **The prompt can't run code.** Values such as the git branch, the path or the host name are passed through `psvar` and shown literally, even with `PROMPT_SUBST` enabled.
- **Clipboard writes from programs are disabled** (OSC 52), and the screen checksum report (DECRQCRA) always answers `0000`.
- **Links** are opened only with ⌘-click and only for `http`, `https`, `mailto` and local `file://` URLs.
- **The AI never runs anything.** Apple Foundation Models runs on the Mac, without network access. Its suggestion is only inserted at the prompt after you confirm it, and you press ⏎ yourself.
- **Release builds** use the Hardened Runtime, have no `get-task-allow` entitlement and are notarized by Apple.
