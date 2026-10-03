<!-- Managed by chezmoi. Edit the source: `chezmoi edit ~/.claude/CLAUDE.md` -->
# Global instructions

## Environment

Dotfiles are managed with chezmoi; the source repo is checked out separately
from `~`. Editing a managed file in `~` directly will be reverted by the next
`chezmoi apply` — edit via `chezmoi edit <path>` instead. Managed files carry a
"Managed by chezmoi" comment at the top.

## Precedence

A project's own CLAUDE.md and its existing conventions override the style rules
below.

## Git

Commit messages follow Conventional Commits (`feat:`, `fix:`, `refactor:`,
`chore:`, `docs:`, `test:`; `!` for breaking changes).  Use scope tags whenever possible, e.g. `feat(parser): ...`

Commit early, commit often - it helps me follow what you did
Use git commit --fixup.  But amend to give it a useful message
Before you start, make sure there is no uncommitted untracked changes.

## Code style

- Follow SOLID and KISS.
- Apply DRY, but AHA.  Abstraction isn't the only tool — prefer tables, data-driven code, or composition where they fit. Don't bloat the codebase to remove duplication, but don't tolerate copy/paste code.
- Avoid boolean parameters and boolean state flags; they usually hide something
  that should be an enumeration.
- Keep functions short: ideally under 8 lines, not counting data declarations
  and error handling. Split when a function does more than one thing.
- A large case / if-elif-else chain may exceed the length limit, but it should
  then be the only thing its function does.
- Keep functions to at most 2 parameters; constructors and similar are exceptions.
- Prefer rewriting unclear code over explaining it with comments.
- Doc comments on public APIs use the language's standard format (Doxygen,
  JSDoc, docstrings, etc.) and stay brief.
- Comments inside function bodies only flag non-obvious pitfalls.

## Communication

When making factual claims (API behaviour, library details, system state,
external facts), tag confidence:
- **fact**: verified or certain enough to swear to in court
- **certain**: high confidence, not verified
- **possible**: plausible, unverified
- **guessing**: speculation

## Machine-local instructions

@~/.claude/CLAUDE.local.md
