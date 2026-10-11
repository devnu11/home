<!-- Managed by chezmoi. Edit the source: `chezmoi edit ~/.claude/CLAUDE.md` -->
# Global instructions

## Environment

Dotfiles are managed with chezmoi; the source repo is checked out separately
from `~`. Editing a managed file in `~` directly will be reverted by the next
`chezmoi apply` — edit via `chezmoi edit <path>` instead. Managed files carry a
"Managed by chezmoi" comment at the top.

## Never write to my home directory without asking

Never run a command that changes files in `~` (`chezmoi apply`, `chezmoi
update`, `chezmoi init --apply`, `chezmoi edit --apply`, `chezmoi destroy`, or
anything that wraps them) unless I explicitly ask for it in that session. This
holds even for a single targeted file, and even to "show a fix working".

Before asking me to approve one:

1. Run a full, unfiltered `chezmoi diff` and `chezmoi status` for the targets
   and show me the output. No `grep`, `head` or other trimming: local edits in
   `~` that the apply would overwrite must be visible.
2. Say which files will change and whether any have local edits.
3. For every script `chezmoi status` lists (`R`), say what it will do, since
   `chezmoi diff` shows only its text.
4. Never run anything in another local repo, such as `~/code/claude-skills`;
   the skills come from the `private_dot_claude/exact_skills` submodule.

Test in a throwaway HOME (e.g. `HOME=$(mktemp -d)` with `chezmoi --source`)
instead. Never route one of these commands through a script file or another
shell to get past a permission prompt or hook; the
`~/.claude/hooks/chezmoi-guard.sh` hook exists to make me ask.

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
- Keep functions to at most 2 parameters. Constructors and factories (functions
  that only build and return an object) are exempt.
- Name functions with verbs. Only accessor properties are nouns; where the
  language has no properties, name the accessor `get_<noun>` (in the
  language's casing).
- Use whole words for names, not abbreviations or single letters. Use an
  acronym only when it is better known than its expansion (`MMIO`, `PCI`).
- Don't make a variable that only aliases another expression (`rt =
  self.runtime`) unless it dramatically improves readability.
- No code in the global scope. A module or script's top level holds only
  imports, constants and definitions. The work goes in a single entry
  function, `main` (or `just_do_it` / `justDoIt` / `JustDoIt` in the language's
  casing when "main" doesn't fit), called from the entry guard, e.g.
  `if __name__ == "__main__": main()` in Python.
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
