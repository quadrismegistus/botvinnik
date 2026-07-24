// The parts of the bridge that are the same whatever hosts the JavaScript.
//
// The two transports (flutter_js on native, the browser on web) cannot share
// a base class — native cannot import dart:js_interop and web cannot import
// dart:ffi. But building the call expression is pure string work with no
// platform dependency, so it lives here rather than being copied into both
// and drifting apart silently.

import 'dart:convert';

/// Bump in lockstep with BRAIN_VERSION in src/lib/brain-entry.ts.
/// Boot fails loudly on mismatch instead of skewing silently.
const int kExpectedBrainVersion = 2;

/// Marker for an omitted argument: marshals as JS `undefined`, engaging the
/// brain's parameter defaults (`now = Date.now()`, `rand = Math.random`).
/// Dart null marshals as JS `null` — the brain's `!== null` guards (e.g.
/// winChance's mate check) must see real null, not undefined.
const Object kOmit = _Omit();

class _Omit {
  const _Omit();
}

/// `JSON.stringify(brain.fn(args…))`, or `JSON.stringify(brain.fn)` when
/// [isProperty]. Both hosts evaluate this same string, which is what makes
/// the golden fixtures mean the same thing on either.
///
/// [global] names the IIFE the bundle hangs off. It is `brain` for brain.js
/// everywhere; the native Maia engine passes `maiaBrain`, its own bundle in
/// its own runtime, so that one marshalling convention covers both rather
/// than the second one being written again from memory.
String buildBrainExpr(String fn, List<Object?> args, bool isProperty,
    {String global = 'brain'}) {
  if (isProperty) return 'JSON.stringify($global.$fn)';
  final encoded = args
      .map((a) => identical(a, kOmit) ? 'undefined' : jsonEncode(a))
      .join(',');
  return 'JSON.stringify($global.$fn($encoded) ?? null)';
}

/// Decodes what the host handed back. `JSON.stringify(undefined)` yields the
/// literal string "undefined".
dynamic decodeBrainResult(String? s) {
  if (s == null || s == 'undefined' || s == 'null') return null;
  return jsonDecode(s);
}
