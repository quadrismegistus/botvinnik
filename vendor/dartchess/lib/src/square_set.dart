// SquareSet has two implementations because a bitboard is 64 bits and a
// JavaScript number is not. Native keeps the original single unboxed int —
// unchanged, so nothing about mobile or desktop performance moves. Web pairs
// two 32-bit halves in a record, which is the only representation that stays
// const-constructible (BigInt and fixnum's Int64 are not, and this class has
// thirteen const bitboards and four const constructors).
//
// Both are validated by the same perft suite. Keep their APIs identical.
export 'square_set_native.dart'
    if (dart.library.js_interop) 'square_set_web.dart';
