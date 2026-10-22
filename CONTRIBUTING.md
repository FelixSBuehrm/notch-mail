# Contributing

Thanks for wanting to make Notch Mail better! This is a small personal project, so the process is light.

## Before you start

- **Small fixes** (typos, bugs, tidy-ups): just open a pull request.
- **Bigger changes** (new provider, new UI states, new dependencies): please open an issue first so we can agree on the shape before you spend an evening on it.
- The [roadmap](README.md#roadmap) lists what's planned. Picking one of those up is great; say so in an issue.

## Getting set up

```sh
git clone https://github.com/FelixSBuehrm/notch-mail.git
cd notch-mail
scripts/test.sh                                     # must be green
scripts/bundle.sh --open                            # build and run
open -n build/NotchMail.app --args --demo-only --demo 3 --capturable   # UI work without an account
```

Command Line Tools are enough; Xcode is optional.

## Ground rules

- **Tests must pass**: `scripts/test.sh`. New behaviour in `NotchCore` or `MailSources` comes with tests (write the failing test first if you can).
- **Keep the layers clean**: `NotchCore` has no AppKit, `MailSources` is Foundation only. UI code lives in `NotchMail`.
- **No new dependencies** without discussing it first.
- **Privacy is a feature**: no mail content on disk, no secrets outside the Keychain, no logging of message content or tokens, no analytics.
- **Never commit real data**: no real email addresses, names, tokens, client IDs or screenshots of a real inbox. Use `example.com` addresses and the demo mail (`--demo-only`).
- Commit messages: `type: short description` (`feat`, `fix`, `refactor`, `docs`, `test`, `chore`).

## AI-assisted contributions

Welcome! Use whatever tools you like, AI coding assistants included. The bar is the same as for hand-written code:

- you've **read and understood** what you're submitting,
- `scripts/test.sh` **passes**, and new behaviour is tested,
- the PR description explains **what and why** in your own words.

Mentioning which tool you used is appreciated but not required. Huge, unreviewed, generated diffs will be closed.

## Code of Conduct

By taking part you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).
