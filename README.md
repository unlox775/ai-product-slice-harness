# AI Product Slice Harness

Build large apps with AI **without** asking one agent to hold the whole system in its head.

This repository is the installable process + runner for slicing a founder vision into **independent product packages**, wiring those packages as **customers of each other**, and running **scoped parallel agents** through clear human-gated phases.

Live demo of the harness in a real product:
[Timelens Photo Scavenger Hunt](https://github.com/unlox775/timelens-photo-scavenger-hunt).

---

## What you are getting into

This is **not** “open a chat and say build me an app that does fifty things.”

That approach collapses on anything non-trivial. Context overflows, boundaries blur, and the agent starts rewriting everything at once.

Instead you get a multi-phase collaboration:

1. You describe the founder vision.
2. AI proposes a few ways to **slice** the vision into independently valuable products.
3. **You** choose the boundaries.
4. AI scaffolds runnable apps plus UI, lib, and datastore packages, stub specs, and customer documents.
5. One planning command runs product specs, then customer requests, then producer responses, with a Git checkpoint after every round.
6. Implementation agents build each package’s MVP and package-local Isolation Demo.
7. You walk the Isolation Demos, write feedback as timestamped specs, and iterate—still one product (or one relationship) at a time.

Humans make product judgment calls at the phase breaks. Agents do scoped package work after those breaks.

Eventually some of the supervision may become more automatic. That is secondary. The load-bearing requirement is a human in the loop who can see the slices, the customer contracts, and the Isolation Demos, and steer when boundaries are wrong.

---

## Core ideas

**Product slices.** Each package should feel like a small company inside the larger company: its own value, inputs, outputs, and a UI you can operate without the final app.

**Customers of each other.** Packages declare consumers in `customers/` documents (producer understanding → customer request → producer response). That is how parallel agents negotiate interfaces without inventing incompatible ones.

**Isolation Demo.** Every package gets exactly one package-local runnable UI
that operates it without the production app. It is the package factory floor and
a standing customer, not another package or phase agent.

**Team-sized slices.** A selected package should be important enough to justify
a long-lived internal team, backlog, and maintenance lifecycle. Pages, forms,
modals, and inspectors stay inside the app or owning package. The slice-up major
headings, imagined team roster, and Phase 03 product agents must match one to
one.

**Scoped agents.** After scaffolding, an agent owns one package or one consumer→producer relationship—not the whole monorepo.

**Plain jobs and explicit data.** Slice plans begin with ordinary verbs, example
inputs and outputs, and a short lexicon. Every proposed piece is labeled as an
`apps/*`, `packages/ui/*`, `packages/lib/*`, or `packages/datastore/*`. Lib and
UI packages own no durable data; datastore packages name their authority.
UI packages are reserved for substantial, independently valuable UI systems—not
ordinary app screens, search forms, inspectors, or component extraction.

**No hidden products.** Every app or package passed to the phase runner must
have a peer-level major heading in the selected alternative. The heading count
is the Phase 03 agent count; supporting bullets cannot silently become packages.

**Visible interfaces.** Every app, package, and store names its main callable
interfaces and concrete screens before scaffolding. Package playgrounds and
store inspectors label fixture, generated, real read-only, and real-write modes
so sample data can never masquerade as the real product.

**Finished picture.** Every slice alternative ends with the founder's future
operating story: what real first case works, which app they open, what they do,
where AI-assisted judgment stops for checks or attention, how they add the next
case, and what useful end state they receive.

---

## The phases

| Phase | Mode | What happens |
|------:|------|--------------|
| **01** | You + IDE agent | Install harness, capture founder vision, propose slice-up alternatives |
| **02** | You + IDE agent | Choose boundaries; scaffold packages, stores, customers, `SUBAGENTS.md`, phase scripts; commit checkpoint |
| **03–05** | Shell planning sequence | Product specs → customer requests → producer responses, with a commit after each round |
| **06** | Shell agents (gated) | First implementation; human confirms before launch |
| **07** | Parallel shell agents | Iterate unresolved timestamped feedback specs; final app last |
| **RA** | IDE + shell | Midstream re-architecture when the first slice was useful but wrong |

Phase 02 is conversational. Background fan-out starts at Phase 03.

The full process document ships into your project as `docs/AI-PRODUCT-SLICE-HARNESS.md`.

---

## Install

From this repo:

```sh
./bin/install /path/to/your-new-or-existing-project
```

Or from inside the project you want to harness:

```sh
/path/to/ai-product-slice-harness/bin/install
```

That copies:

- `docs/AI-PRODUCT-SLICE-HARNESS.md` — the process
- `docs/ai-product-slice-harness/` — runner, watchers, feedback helper, phase-script generator, config
- `subagents/` — status tools, re-architecture phases, examples
- `scripts/generate-phase-07-notes.py`
- `Makefile.harness` (+ `include` from your `Makefile`)
- starter `SUBAGENTS.md` and `docs/VERSION-HISTORY.md` if missing

Then the installer prints Phase 01 next steps.

### Right after install

```sh
cd /path/to/your-project
make harness-help
```

1. Dictate the founder vision to your IDE agent (or write `docs/FOUNDER-vision.md`).
2. Ask it to write the root README and a slice-up plan (`docs/SLICE-UP-plan.md`).
3. Choose a slice-up philosophy.
4. Scaffold packages / customer stubs, then generate Phase 03–07 scripts:

```sh
bash docs/ai-product-slice-harness/write-phase-scripts.sh --help
```

5. Start the persistent watcher once, then run all three planning rounds:

```sh
make watch
HARNESS_COMMIT_DIRTY=1 make phase-2-5
# Or, when Phase 02 is already committed: make phase-3-5
PHASE_CONFIRMED=1 make phase-6
make phase-7-dry-run
make phase-7
```

`phase-2-5` refuses to include existing local changes until you explicitly set
`HARNESS_COMMIT_DIRTY=1` after reviewing them. `phase-3-5` requires a clean
worktree. Both stop on a blocked or failed round. `make watch` remains open and
automatically follows the current phase; pin `PHASE=...` only when debugging.

Create feedback during Phase 07 with:

```sh
bash subagents/new-feedback.sh packages/your-product "Short feedback title"
```

---

## Requirements

- **Phase 01–02:** any capable IDE coding agent (Cursor, etc.).
- **Phase 03+ shell fan-out:** [Codex CLI](https://github.com/openai/codex) (`codex` on `PATH`). The runner invokes `codex exec` with a workspace-write sandbox by default.
- **macOS-friendly watchers** and optional iOS `CODEX_ADD_DIRS` when you pass `--ios-sandbox` to the phase-script generator.

---

## Repository layout

```text
bin/install                 # copies the harness into a target project
template/                   # files installed into projects
  docs/AI-PRODUCT-SLICE-HARNESS.md
  docs/ai-product-slice-harness/
  subagents/
  scripts/
  Makefile.harness
README.md                   # you are here
```

Project-specific phase scripts (`phase-03`…`phase-07`) are **generated per project** after slice-up selection. Re-architecture scripts are generic and install ready to run.

---

## Demo: Timelens

[Timelens Photo Scavenger Hunt](https://github.com/unlox775/timelens-photo-scavenger-hunt) used this process end-to-end: founder vision → slice-up → parallel package agents → customer contracts → package Isolation Demos → final iOS app → Phase 07 feedback loops → a midstream re-architecture when ownership boundaries needed to move.

That repo still uses an earlier on-disk naming (`docs/STANDARD-project-harness.md`). This repository is the cleaned, installable extraction of the mature harness.

---

## Status

Working extraction of the process and runner that grew up inside Timelens. Install, configure, scaffold phase scripts, and run the phased build.
