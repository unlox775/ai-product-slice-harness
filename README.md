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
4. AI scaffolds packages, stub specs, and customer documents.
5. Parallel agents write product specs, then customer requests, then producer responses.
6. Implementation agents build each package’s MVP and a direct-observation showcase.
7. You walk the showcases, write feedback as timestamped specs, and iterate—still one product (or one relationship) at a time.

Humans make product judgment calls at the phase breaks. Agents do scoped package work after those breaks.

Eventually some of the supervision may become more automatic. That is secondary. The load-bearing requirement is a human in the loop who can see the slices, the customer contracts, and the showcases, and steer when boundaries are wrong.

---

## Core ideas

**Product slices.** Each package should feel like a small company inside the larger company: its own value, inputs, outputs, and a UI you can operate without the final app.

**Customers of each other.** Packages declare consumers in `customers/` documents (producer understanding → customer request → producer response). That is how parallel agents negotiate interfaces without inventing incompatible ones.

**Direct observation.** Every slice gets a concrete showcase. If the machine emits events or transforms data, you can watch it happen.

**Scoped agents.** After scaffolding, an agent owns one package or one consumer→producer relationship—not the whole monorepo.

---

## The phases

| Phase | Mode | What happens |
|------:|------|--------------|
| **01** | You + IDE agent | Install harness, capture founder vision, propose slice-up alternatives |
| **02** | You + IDE agent | Choose boundaries; scaffold packages, customers, `SUBAGENTS.md`, phase scripts |
| **03** | Parallel shell agents | One product-spec agent per package |
| **04** | Parallel shell agents | One customer-request agent per relationship |
| **05** | Parallel shell agents | One producer-response agent per package |
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

5. Run phases with human review between them:

```sh
make phase-3
make phase-4
make phase-5
PHASE_CONFIRMED=1 make phase-6
make phase-7-dry-run
make phase-7
make watch
```

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

[Timelens Photo Scavenger Hunt](https://github.com/unlox775/timelens-photo-scavenger-hunt) used this process end-to-end: founder vision → slice-up → parallel package agents → customer contracts → package showcases → final iOS app → Phase 07 feedback loops → a midstream re-architecture when ownership boundaries needed to move.

That repo still uses an earlier on-disk naming (`docs/STANDARD-project-harness.md`). This repository is the cleaned, installable extraction of the mature harness.

---

## Status

Working extraction of the process and runner that grew up inside Timelens. Install, configure, scaffold phase scripts, and run the phased build.
