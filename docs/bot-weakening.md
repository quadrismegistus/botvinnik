# Making the bot play convincingly weak

Research notes + direction for botvinnik-web's practice bot, focused on the
hard part: **realistic play below Stockfish's UCI_Elo ~1320 floor, without the
"swingy / inhuman" feel** of the current softmax sampler.

Compiled 2026-07-14 from a three-agent literature/source sweep. Facts are
cited; inferences are marked. Confidence noted per claim at the end.

## The core diagnosis

Every source converges on one insight:

> **Inhuman weakness comes from making _position-independent, unbounded_
> mistakes.** Real weak players blunder in _specific, predictable contexts_ and
> almost never hang a piece for nothing. A temperature/softmax sampler blunders
> _uniformly_ — including in easy positions — and occasionally throws away
> everything.

Our current `selectBotMove` (softmax over centipawn scores across MultiPV) is
exactly this. Maia-2's paper names the pathology **"incoherence"**: play well,
one catastrophe, then fine again — which is precisely what Ryan felt testing
the 1000 bot game-to-game.

## What Stockfish's own knobs do (and their ceiling)

`UCI_Elo` is a front-end that converts a target Elo into the internal **Skill
Level (0–20)** via a power curve
(`clamp(pow((UCI_Elo − 1346.6)/143.4, 1/0.806), 0, 20)`, commit `a08b8d4`,
anchored to CCRL 40/4). Skill then weakens play two ways (`search.cpp`):

1. **Effective depth cap** — the move is picked at `depth = 1 + level` (Skill 0
   ≈ depth-1 search).
2. **Weighted-random pick from MultiPV≥4** — `Skill::pick_best` adds
   `weakness = 120 − 2·level` of noise to each candidate but **clamps the window
   to one pawn** (`delta ≤ PawnValue`), so the chosen inferior move is provably
   within ~1 pawn of best. Genuinely per-move RNG (seeded by `now()`).

**The 1320 floor is a calibration choice, not a safety limit**: 1320 clamps to
Skill 0, and everything 1320–~1347 collapses onto it. There is no honest way
lower within Stockfish. And the Stockfish devs themselves document that the
result is (a) shallow-but-tactically-sharp (won't hang like a beginner) and
(b) randomly swingy/inhuman (issues #3635, #2817). Their own RFC explored
replacing it with **NNUE eval perturbation** but never adopted it.

Note the clamp-to-1-pawn: even Stockfish adds an explicit anti-absurdity floor.
That is a hint for us.

## Technique landscape (ranked for a WASM app)

| Approach | Mechanism | Verdict |
|---|---|---|
| **Bounded, position-adaptive windowed sampling over MultiPV** | Sample among candidates within a **win-probability** window, but collapse the window in easy/forcing/few-reply positions and on free-material/mate-in-1 | **★ Best low-cost path.** What Stockfish/Komodo/chess.com effectively do. Pure JS over our existing MultiPV output. |
| **Per-game-stable regime + free-material guard** | Fix the RNG regime + window width for a whole game; bias toward any winning capture so the bot never misses free material | **★ Complements the above.** Fixes coherence and the #1 "feels broken" tell. |
| Evaluation noise (Gaussian on eval) | Perturb scores inside search | **Avoid.** Uncalibrated; the **Beal effect** means random eval + deep search paradoxically plays _stronger_ (~1700). |
| Search / depth / node limiting alone | Shallow fixed search | **Compounding throttle only.** A shallow search still resolves 1–2 move tactics → plays _inhumanly solid_; Maia showed depth-limiting is non-monotonic vs human agreement. |
| **Maia** (human-imitation net) | Predicts the move a human of rating X actually plays | **★ The human-feel ceiling.** Separate net; see below. |

## What the big platforms actually do

- **Lichess levels 1–8** = Skill Level + shallow depth + short movetime combined
  (`lichess-org/fishnet`). Levels 1–3 use _negative_ Skill, only possible on
  their Fairy-Stockfish build — **vanilla Stockfish.js clamps at 0**, so we
  can't copy their easiest levels directly. Lichess added **Maia bots** because
  weakened Stockfish feels wrong (`lila` #13537).
- **chess.com bots** (Martin ≈ 250) run **weakened Komodo** ("komodo-lite" WASM,
  client-side like us) + tiny amateur-emulating nets below ~2400 + **custom
  human opening books per persona**.
- **Fritz / Shredder** _adapt to the player_ and are described as making
  "typical human mistakes" and "creating tactical chances" rather than hanging
  pieces; Shredder caps down to ~850.

## Maia — the human-feel ceiling, and it's browser-viable

Maia (McIlroy-Young et al., KDD 2020) is a Leela-style net trained on human
games **per rating band** to predict the move a human of that band would play —
so it makes _characteristic_ errors (missed one-move tactics, weak king safety,
botched basic endgames) instead of random ones. Nine nets, **Maia-1100…1900**.

- **It already runs in-browser** via **ONNX Runtime Web**, alongside
  Stockfish.js — the lab's own `maia-platform-frontend` and community
  `hunterchen7/play-lc0` do exactly this. Nets are **small (~1 MB)**,
  IndexedDB-cached, and because Maia uses **no tree search** (one policy
  forward-pass per move), inference is **cheaper than a Stockfish depth
  search**.
- **Caveats:** Maia-1100 is **mis-calibrated at the bottom** — averaging human
  moves removes band-specific blunders, so it plays ~1500 and blunders _less_
  than a real beginner. It gives **only a move, no eval** (we keep Stockfish for
  analysis/hints). It's a **separate net**, not reachable through Stockfish.js.
- **Newer follow-ups reported but UNVERIFIED** (post knowledge-cutoff, from live
  search — verify before relying): **Maia-2** (arXiv 2409.20553, a single
  skill-conditioned model; solid), and 2026-dated **Maia-3/"Chessformer"**,
  **Allie**, **ChessMimic** claiming coverage down to ~600. Treat the specifics
  as unconfirmed.

## Recommendation / direction for botvinnik

1. **Evolve `selectBotMove` into a bounded, position-adaptive sampler** — three
   changes, all within the current Stockfish.js + MultiPV setup, near-zero cost:
   - sample within a **win-probability window** (cp → win% first), not raw
     softmax over cp;
   - **collapse the window to the best move** when it's far ahead of #2, when
     there are few legal replies, or on recaptures/mate-in-1 — _don't blunder in
     easy positions_;
   - fix the window width **per game**, not per move, so a "900" is a coherent
     900 all game.
2. **Add a free-material guard** — a shallow scan so the bot never misses
   hanging material (the #1 thing that makes weak bots feel broken).
3. **For authentic error _placement_ at the sub-1320 bands: add Maia as ONNX**
   in-browser (a separate move provider used for the low bands; Stockfish stays
   for analysis/hints and the strong bands). Bigger lift but the ceiling for
   "feels human." See the integration plan below / in ROADMAP.

Steps 1+2 get ~80% of the human feel at near-zero cost inside our exact
UCI+MultiPV constraint; step 3 is the upgrade.

## Where Maia slots into the current architecture

Bot moves flow `maybeBotMove` → `analyzeBotMove` (weakened Stockfish) →
`selectBotMove` (sampler), all behind `TransportFactory`. Maia is **not** a UCI
engine, so it doesn't fit the transport abstraction — it's its own module
(e.g. `src/lib/engine/maia.ts`) returning a move from a policy forward-pass.
The insertion point is `maybeBotMove`: when `botElo` is in Maia's band, call
`maiaMove(fen, elo)` instead of the Stockfish sample; otherwise unchanged.

## Sources

Stockfish: [search.cpp](https://github.com/official-stockfish/Stockfish/blob/master/src/search.cpp),
[FAQ](https://official-stockfish.github.io/docs/stockfish-wiki/Stockfish-FAQ.html),
[Elo commit a08b8d4](https://github.com/official-stockfish/Stockfish/commit/a08b8d4),
[issue #3635](https://github.com/official-stockfish/Stockfish/issues/3635),
[#2817](https://github.com/official-stockfish/Stockfish/issues/2817).
Maia: [KDD 2020 paper](https://www.cs.toronto.edu/~ashton/pubs/maia-kdd2020.pdf),
[maiachess.com](https://www.maiachess.com/), [CSSLab/maia-chess](https://github.com/CSSLab/maia-chess),
[maia-2 arXiv 2409.20553](https://arxiv.org/abs/2409.20553),
[maia-platform-frontend](https://github.com/CSSLab/maia-platform-frontend),
[play-lc0](https://github.com/hunterchen7/play-lc0).
Platforms: [lichess-org/fishnet](https://github.com/lichess-org/fishnet),
[lila #13537](https://github.com/lichess-org/lila/issues/13537),
[Shredder FAQ](https://www.shredderchess.com/faq.html).
Sampling critique: [Transcendence, arXiv 2406.11741](https://arxiv.org/abs/2406.11741),
[CPW Playing Strength](https://www.chessprogramming.org/Playing_Strength).

## Confidence

- Stockfish Skill formula, MultiPV≥4, `depth = 1+level`, 1320/3190 range, the
  1-pawn clamp — **high** (source code, cross-verified by two agents + a direct
  fetch).
- Lichess level table shape — **high**; precise current values — **medium**
  (fishnet releases drift).
- chess.com/Komodo internals — **medium** (credible dev-forum statements, no
  official engineering post).
- Maia-1 / Maia-2 / in-browser ONNX deployment — **high** (peer-reviewed +
  public repos).
- Maia-3 / Allie / ChessMimic specifics — **low / unverified** (post-cutoff).
