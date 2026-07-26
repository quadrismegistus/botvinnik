#!/usr/bin/env python3
"""Chess-GPT as a UCI engine, so the gym can measure it (#183 seam).

Adam Karvonen's nanoGPT models trained on PGN text — a family that varies only
in TRAINING CORPUS at fixed architecture (lichess human games / Stockfish
self-play / a mix / an untrained control), which is what makes it worth
measuring here rather than just interesting. Our own bots are all one engine
dialled down; these are models that learned chess from different teachers, and
the open question is whether their mistakes have different SHAPES at matched
strength. The gym already answers "how strong"; this plugs a genuinely
different kind of player into the same ruler.

  models:  https://huggingface.co/adamkarvonen/chess_llms
  paper:   https://arxiv.org/abs/2403.15498

THE BIG CONSTRAINT, stated up front: this model conditions on MOVETEXT, not on
a position. Its whole input is a PGN prefix like ";1.e4 e5 2.". There is no way
to hand it a FEN — a mid-game position with no history is off-distribution and
it will produce noise. So `position fen ...` is REFUSED loudly (see
_cmd_position) rather than answered badly. Games must start from the standard
position. This is a property of the model, not of the shim.

UCI subset: uci / isready / setoption name Model|Temperature value X /
ucinewgame / position startpos [moves ...] / go (search params ignored — a
forward pass has no depth to vary) / quit.

  scripts/engines/chessgpt/setup.sh          # venv + deps + weights
  scripts/engines/chessgpt/run.sh            # what the gym spawns
"""
import os
import pickle
import sys
import time

import chess
import torch
import torch.nn as nn
import torch.nn.functional as F

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_MODEL = "lichess_8layers_ckpt_no_optimizer.pt"

# How many characters a SAN token can run to. The longest legal SAN is 7
# ("Qa1xb2#" style disambiguation + capture + mate); 10 leaves room and still
# bounds a runaway sample.
MAX_SAN_CHARS = 10


class Block(nn.Module):
    """One nanoGPT transformer block, bias-free (the checkpoints set bias=False)."""

    def __init__(self, d: int, h: int):
        super().__init__()
        self.h = h
        self.ln_1 = nn.LayerNorm(d, bias=False)
        self.attn_c_attn = nn.Linear(d, 3 * d, bias=False)
        self.attn_c_proj = nn.Linear(d, d, bias=False)
        self.ln_2 = nn.LayerNorm(d, bias=False)
        self.mlp_c_fc = nn.Linear(d, 4 * d, bias=False)
        self.mlp_c_proj = nn.Linear(4 * d, d, bias=False)

    def forward(self, x):
        B, T, C = x.shape
        q, k, v = self.attn_c_attn(self.ln_1(x)).split(C, dim=2)
        q = q.view(B, T, self.h, C // self.h).transpose(1, 2)
        k = k.view(B, T, self.h, C // self.h).transpose(1, 2)
        v = v.view(B, T, self.h, C // self.h).transpose(1, 2)
        y = F.scaled_dot_product_attention(q, k, v, is_causal=True)
        x = x + self.attn_c_proj(y.transpose(1, 2).contiguous().view(B, T, C))
        return x + self.mlp_c_proj(F.gelu(self.mlp_c_fc(self.ln_2(x))))


class GPT(nn.Module):
    def __init__(self, cfg: dict):
        super().__init__()
        d, L, H = cfg["n_embd"], cfg["n_layer"], cfg["n_head"]
        self.block_size = cfg["block_size"]
        self.wte = nn.Embedding(cfg["vocab_size"], d)
        self.wpe = nn.Embedding(self.block_size, d)
        self.blocks = nn.ModuleList([Block(d, H) for _ in range(L)])
        self.ln_f = nn.LayerNorm(d, bias=False)
        self.lm_head = nn.Linear(d, cfg["vocab_size"], bias=False)
        self.lm_head.weight = self.wte.weight  # nanoGPT ties input/output embeddings

    def forward(self, idx):
        T = idx.shape[1]
        x = self.wte(idx) + self.wpe(torch.arange(T, device=idx.device))
        for b in self.blocks:
            x = b(x)
        return self.lm_head(self.ln_f(x))


def _load(model_file: str):
    """The checkpoint, mapped onto the module names above.

    `_orig_mod.` is a torch.compile artifact from training; the rest is
    ordinary nanoGPT naming flattened by one level. Loaded with strict=True so
    a rename upstream fails here rather than silently leaving a layer at its
    random initialisation — a model with one untrained block still emits
    plausible-looking SAN, so nothing downstream would notice.
    """
    path = os.path.join(HERE, "weights", model_file)
    if not os.path.exists(path):
        sys.exit(f"missing weights: {path}\nrun scripts/engines/chessgpt/setup.sh")
    ck = torch.load(path, map_location="cpu", weights_only=False)
    model = GPT(ck["model_args"]).eval()
    remap = {}
    for k, v in ck["model"].items():
        k = (
            k.replace("_orig_mod.", "")
            .replace("transformer.", "")
            .replace("h.", "blocks.")
            .replace(".attn.c_attn", ".attn_c_attn")
            .replace(".attn.c_proj", ".attn_c_proj")
            .replace(".mlp.c_fc", ".mlp_c_fc")
            .replace(".mlp.c_proj", ".mlp_c_proj")
        )
        remap[k] = v
    # lm_head is TIED to wte, so the checkpoint carries only one of them —
    # but load_state_dict still wants the key, and dropping to strict=False to
    # sidestep that would also stop catching a genuine rename, which is the
    # whole reason for strict. Feed it the tied tensor instead.
    remap.setdefault("lm_head.weight", remap["wte.weight"])
    model.load_state_dict(remap, strict=True)
    with open(os.path.join(HERE, "meta.pkl"), "rb") as f:
        meta = pickle.load(f)
    return model, meta["stoi"], meta["itos"]


class ChessGPT:
    def __init__(self):
        self.model_file = DEFAULT_MODEL
        self.temperature = 0.0
        self.model = None
        self.stoi = self.itos = None
        self.board = chess.Board()
        self.pgn = ";"
        # False after a position we cannot represent. Without it, `go` answered
        # from whatever the LAST valid position was — a legal-looking move for
        # a different board, which is the worst kind of wrong: a caller that
        # ignored the refusal would get a plausible reply and never know.
        self.ready = True

    def ensure_loaded(self):
        if self.model is None:
            self.model, self.stoi, self.itos = _load(self.model_file)

    @torch.no_grad()
    def _sample_san(self, temperature: float) -> str:
        """Characters until the move token closes, or we run out of patience.

        The move NUMBER is part of the prompt, not of the stored movetext: in
        PGN a white move is preceded by "12." and a black one by nothing, so
        without it the model is asked to continue ";1.e4 e5 " and dutifully
        starts writing "2" — which is not a SAN and fails to parse, six times
        over. Black-to-move worked and white-to-move did not, which is exactly
        how this showed up.
        """
        prompt = self.pgn
        if self.board.turn == chess.WHITE:
            prompt += f"{self.board.fullmove_number}."
        ids = [self.stoi[c] for c in prompt if c in self.stoi]
        # The context is a fixed 1023 positions; keep the TAIL, which is the
        # recent play. A game long enough to overflow is already off the
        # distribution these were trained on, so this is damage limitation.
        ids = ids[-self.model.block_size:]
        idx = torch.tensor([ids], dtype=torch.long)
        out = ""
        for _ in range(MAX_SAN_CHARS):
            logits = self.model(idx)[:, -1, :]
            if temperature <= 0:
                nxt = int(logits.argmax(-1))
            else:
                probs = F.softmax(logits / temperature, dim=-1)
                nxt = int(torch.multinomial(probs, 1))
            ch = self.itos[nxt]
            if ch in " ;" and out:
                break
            out += ch
            idx = torch.cat([idx, torch.tensor([[nxt]])], dim=1)
        return out.strip()

    def best_move(self) -> str:
        """A UCI move string, or '0000' if we could not get a legal one.

        Retried WITH TEMPERATURE rather than falling back to a random legal
        move: a random move is a different player silently wearing this one's
        name, and it would corrupt exactly the measurement this engine exists
        to make. Resigning the point by returning 0000 is visible in the gym
        output; a random move is not.
        """
        if not self.ready:
            return "0000"
        self.ensure_loaded()
        for attempt in range(6):
            temp = self.temperature if attempt == 0 else max(0.5, self.temperature)
            san = self._sample_san(temp)
            try:
                move = self.board.parse_san(san)
            except Exception:
                continue
            return move.uci()
        return "0000"

    def _cmd_position(self, parts: list[str]) -> None:
        if "fen" in parts:
            # See the module docstring: there is no honest answer here.
            print(
                "info string chessgpt: FEN positions are unsupported — this "
                "model conditions on movetext, not on a position",
                flush=True,
            )
            self.ready = False
            return
        self.ready = True
        self.board = chess.Board()
        self.pgn = ";"
        if "moves" in parts:
            for uci in parts[parts.index("moves") + 1:]:
                move = chess.Move.from_uci(uci)
                if self.board.turn == chess.WHITE:
                    self.pgn += f"{self.board.fullmove_number}."
                self.pgn += self.board.san(move) + " "
                self.board.push(move)

    def run(self) -> None:
        for raw in sys.stdin:
            line = raw.strip()
            if not line:
                continue
            parts = line.split()
            cmd = parts[0]
            if cmd == "uci":
                print("id name Chess-GPT (%s)" % self.model_file)
                print("id author Adam Karvonen (model); botvinnik (UCI shim)")
                print("option name Model type string default %s" % DEFAULT_MODEL)
                print("option name Temperature type string default 0.0")
                print("uciok", flush=True)
            elif cmd == "isready":
                self.ensure_loaded()  # pay the load here, not inside a timed go
                print("readyok", flush=True)
            elif cmd == "setoption":
                if "Model" in parts:
                    self.model_file = parts[-1]
                    self.model = None  # reload lazily
                elif "Temperature" in parts:
                    self.temperature = float(parts[-1])
            elif cmd == "ucinewgame":
                self.board = chess.Board()
                self.pgn = ";"
                self.ready = True
            elif cmd == "position":
                self._cmd_position(parts)
            elif cmd == "go":
                t0 = time.time()
                mv = self.best_move()
                print("info string %.0fms" % ((time.time() - t0) * 1000), flush=True)
                print("bestmove %s" % mv, flush=True)
            elif cmd == "quit":
                return


if __name__ == "__main__":
    ChessGPT().run()
