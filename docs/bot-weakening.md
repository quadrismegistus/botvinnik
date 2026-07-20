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

## Anchoring findings + coverage map + the low-end plan (2026-07-14)

Ran our WASM Stockfish bands against Maia-1 and Maia-3 in the harness
(data/bot-maia3-anchor.json, n=100). Two robust findings:

1. **Our softmax sampler is the _wrong kind_ of weak — measured.** Every one of
   our bands lost ~95% to _every_ Maia, including Maia-3 dialed to its weakest
   (600). Our "1500" gets crushed by a coherent bot dialed to 600, because our
   sampler blunders _randomly and uniformly_ and random blunders are
   exploitable. This empirically confirms the whole thesis and means the sampler
   can't be cleanly anchored to a human scale (it's a different _kind_ of
   player).
2. **Maia-3 is a real dial but floors at CLUB level — it does NOT reach
   beginner.** Internal ladder: maia3:600→1900 spans ~600 real Elo (monotonic).
   Bridge to Maia-1's measured lichess ratings (@maia1=1572, @maia5=1643,
   @maia9=1701 rapid): maia3:X plays ~150–270 STRONGER than maia:X, so even
   maia3:600 lands ~lichess-1500–1550 rapid. Imitating human moves — even
   "beginner" ones — yields sound-enough _games_ (misses tactics but plays
   coherently) that the floor stays club-ish. Less compressed than Maia-1, but
   the fundamental Maia limitation holds. (Measured at temperature 0.5; higher
   temp lowers the floor but re-adds randomness — the knob fight.)

### Coverage map — which model for which band

| Target (lichess rapid ≈) | Model | Status |
|---|---|---|
| **~800–1500 (true beginner → lower club) — Ryan's range** | **coherent shaped-blunder sampler** (Stockfish + human-error model) | **to build** — the real gap |
| ~1500–2000 (club) | **Maia-3** (human-like, ELO-dialed, anchorable to lichess) | integrated on `maia-bot`; adopt for this band |
| ~2000+ (strong) | Stockfish (UCI_Elo / high-α sampler) | shipped |

Neither Maia nor the current random sampler serves ~800–1500 convincingly. That
band — which includes Ryan (chess.com 550–830 ≈ lichess ~800–1100) — needs a
purpose-built coherent-weak bot.

### The low-end answer: coherent shaped-blunder sampler

Evolve `selectBotMove` from "softmax over all MultiPV" into a coherent weak
player that plays sound chess and makes _bounded, human-shaped_ mistakes:

1. **Play the engine-best move most of the time** (coherent baseline — the thing
   the random sampler lacks).
2. **With a rating-dependent probability p(elo), make a mistake** — pick an
   inferior move, but BOUND it: (a) severity capped (eval drop ≤ a
   rating-scaled window, so weaker players make bigger but not absurd errors);
   (b) window is over WIN-PROBABILITY, not raw cp (so it self-tightens in
   balanced positions, loosens in decided ones).
3. **Position-adaptive** — collapse the mistake window to zero in easy/forcing
   positions (few legal replies, only-move, recapture, mate-in-1). The
   swinginess came from blundering _uniformly_, including in easy spots.
4. **Per-game-stable regime** — fix p(elo) and the window for a whole game, so a
   "900" is a coherent 900, not a per-move dice roll.
5. **Human-shaped error TYPES** — bias mistakes toward realistic human misses
   (overlook a fork/pin, misjudge a trade, back-rank) rather than random legal
   moves; forbid free single-move hangs unless a beginner realistically would.

This is what chess.com's beginner bots (Martin ≈ 250) actually do — weakened
engine + engineered, bounded error injection + human opening books — precisely
because pure imitation (Maia) averages out beginner blunders and floors too
high.

### On training a net on a beginner corpus (the imitation ceiling)

"Could we train on human games at particular Elo bands?" — **that is exactly
what Maia already is** (trained on lichess games bucketed by rating). The
problem isn't lack of data; it's that **imitating the _average_ move of a band
washes out the band's blunders** — beginners err in _diverse_ ways that average
to a sound move, so the model plays stronger than the band (Maia-1100 → ~1500).
Maia-2/3's skill-conditioning helps but doesn't fully fix it (maia3:600 still
~1550). So retraining on a beginner corpus would hit the same ceiling. What a
corpus IS good for: **calibrating the shaped-blunder model above** — measure
from real ~800-rated games how often and how badly beginners actually err, and
in what contexts (opening/middlegame/endgame, tactic types), then reproduce that
error PROFILE on top of Stockfish. That models the error _distribution_, not the
average move — which is the thing imitation can't capture. (Related research:
Maia-Individual / personalized Maia; the broader "designing weak but human-like
game AI" line. The convincing-beginner problem is genuinely unsolved by
imitation alone, which is why industry beginner bots are engineered.)

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

## Maia in-browser: integration spec (verified 2026-07-14 from source)

Two working browser reference implementations exist, taking different paths:

- **Path A — raw lc0/Maia-1 net** (`hunterchen7/play-lc0`, TypeScript): original
  CSSLab `.pb.gz` converted to ONNX, run as a standard Lc0 net. 112-plane input
  `[1,112,8,8]`, 1858-move policy, **one net per rating band, no ELO input**.
  Small (~3.3 MB ONNX/band). **Pre-converted ONNX on HuggingFace**
  (`shermansiu/maia-1900/resolve/main/model.onnx`, 3.48 MB).
- **Path B — Maia-3** (`CSSLab/maia-platform-frontend`): single **ELO-conditioned**
  transformer. Token input (64×12) + two scalar ELO inputs, 4352-move policy,
  LDW value head. One model, **44 MB** (`public/maia3/maia3_simplified.onnx`; no
  official HF ONNX — that export is the only one).

**Files to port (Path A):** `play-lc0/src/engine/{encoding.ts, decoding.ts,
policyIndex.ts (the 1858 index→UCI table), inference.ts, modelCache.ts,
worker.ts}`.

**Encoding (load-bearing, verified):** `encodeFenHistory` → `Float32Array(112*64)`.
Planes 0–103 = 13 planes × 8 history positions (6 own + 6 opp piece bitboards +
1 repetition); 104–107 castling; 108 black-to-move; 109 rule50 (capped 1); 110
zeros; 111 ones. **Black to move: relabel pieces us/them AND vertical rank flip
(`7-rank`); swap castling to us/them.** Maia-1 was *trained with move history* —
feeding only the current position (zeros elsewhere) measurably shifts its move
distribution. botvinnik HAS the live game history, so we can feed real prior
FENs and keep fidelity.

**Decoding (verified):** softmax over **legal moves only** via the 1858
`POLICY_INDEX` (White POV; flip black UCIs to canonical, strip knight-promo `n`);
temperature 0 = argmax, >0 = sample; return the original (un-flipped) UCI.

**onnxruntime-web:** run in a Web Worker, cache weights in IndexedDB. **Use
`numThreads=1`** (single policy eval; keeps us off `SharedArrayBuffer` → no
COOP/COEP cross-origin-isolation headers, matching our no-SAB lite-single
setup). Providers `["wasm"]` (+ `"webgpu"` opportunistically). Copy
`onnxruntime-web/dist/ort-wasm*` into a static dir; point `ort.env.wasm.wasmPaths`
there. Serve `.onnx` from `vendor/` (was `static/` before 2026-07-20).

**Licensing:** GPL-3.0 weights → **don't bundle**; `fetch()` from an external URL
(HuggingFace or our bucket) at runtime + IndexedDB cache. App code stays
separate, not a derivative. Manageable, not a blocker.

**Top risks:** (1) encoding fidelity — the us/them relabel + rank-flip for black
is subtle and yields plausible-but-wrong moves if off; validate against known
Maia move probabilities on a few FENs. (2) history planes (see above). (3)
ort-**web** export compat — a known Lc0 float64/float32 value-head bug and
opset/WebGPU-op issues; test the specific `.onnx` under ort-web, not just
ort-node.

**CRITICAL COVERAGE NUANCE:** Maia-1's lowest band (Maia-1100) is mis-calibrated
and plays ~1500, blundering _less_ than a real beginner — so Path A covers the
**~1100–1900 club range** but NOT the true-beginner bottom (Ryan plays ~550–830).
Only Maia-3 (Path B, 44 MB, less verified) claims down to ~600. So Maia
complements but does not replace the bounded-sampler work for the very bottom.

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
