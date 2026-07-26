#!/usr/bin/env python3
"""Export a Chess-GPT checkpoint to ONNX, so the app can run it through the
onnxruntime it already ships for Maia.

The app has no PyTorch and never will. ORT is the existing native path
(maia_engine_io.dart), so getting there is the whole question — everything
downstream is a well-trodden road in this codebase.

Two decisions worth stating:

  * The graph returns ONLY the final position's logits. Sampling needs the
    next character and nothing else, so returning the full (1, T, 32) tensor
    would ship T-1 rows across the FFI boundary to be thrown away.

  * Dynamic sequence length. The prompt grows by a few characters per move and
    a game can reach the full 1023-token context, so a fixed-length graph would
    mean padding every call to the maximum — paying full context cost from move
    one.

    bash scripts/shims/chessgpt/export_onnx.py --model <file> [--quantize]
"""
import argparse
import os
import sys

import torch

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from chessgpt_uci import GPT, _load  # noqa: E402


class LastLogits(torch.nn.Module):
    """The model, narrowed to what sampling actually consumes."""

    def __init__(self, gpt: GPT):
        super().__init__()
        self.gpt = gpt

    def forward(self, idx: torch.Tensor) -> torch.Tensor:
        return self.gpt(idx)[:, -1, :]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="lichess_8layers_ckpt_no_optimizer.pt")
    ap.add_argument("--out", default=None)
    ap.add_argument("--quantize", action="store_true")
    args = ap.parse_args()

    model, stoi, itos = _load(args.model)
    wrapped = LastLogits(model).eval()

    out = args.out or os.path.join(
        HERE, "onnx", args.model.replace("_ckpt_no_optimizer.pt", "").replace(".pt", "") + ".onnx"
    )
    os.makedirs(os.path.dirname(out), exist_ok=True)

    # A realistic prompt length, not 1: exporting from a degenerate shape is how
    # a graph ends up with a baked-in sequence dimension that only shows up as
    # a shape error on the first real call.
    example = torch.randint(0, 32, (1, 24), dtype=torch.long)

    torch.onnx.export(
        wrapped,
        (example,),
        out,
        input_names=["tokens"],
        output_names=["logits"],
        dynamic_axes={"tokens": {1: "seq"}, "logits": {}},
        opset_version=17,
        do_constant_folding=True,
    )
    size = os.path.getsize(out) / 1e6
    print(f"exported {out}  ({size:.1f} MB)")

    # Numerics, against the source of truth. An export that runs but drifts is
    # worse than one that fails: it plays slightly different chess and nothing
    # says so.
    try:
        import onnxruntime as ort
        import numpy as np

        sess = ort.InferenceSession(out, providers=["CPUExecutionProvider"])
        worst = 0.0
        for seq in (8, 24, 97):
            probe = torch.randint(0, 32, (1, seq), dtype=torch.long)
            with torch.no_grad():
                ref = wrapped(probe).numpy()
            got = sess.run(["logits"], {"tokens": probe.numpy()})[0]
            worst = max(worst, float(np.abs(ref - got).max()))
            # The ARGMAX is what actually decides a move at temperature 0.
            assert ref.argmax() == got.argmax(), f"argmax differs at seq={seq}"
        print(f"  numerics ok — max |Δlogit| = {worst:.2e}, argmax matches at every length")
    except ImportError:
        print("  (onnxruntime not installed; skipped the numerical check)")

    if args.quantize:
        try:
            from onnxruntime.quantization import quantize_dynamic, QuantType

            q = out.replace(".onnx", ".int8.onnx")
            quantize_dynamic(out, q, weight_type=QuantType.QInt8)
            print(f"quantized {q}  ({os.path.getsize(q)/1e6:.1f} MB)")
        except ImportError:
            print("  (onnxruntime.quantization unavailable; skipped)")


if __name__ == "__main__":
    main()
