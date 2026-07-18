import './models.dart';

/// A finite set of all squares on a chessboard — web implementation.
///
/// A bitboard is 64 bits and a JavaScript number is not, so the set is stored
/// as a record of two 32-bit halves, `(lo, hi)`, little-endian rank-file
/// mapped exactly as the native version: square `s` lives in `lo` when
/// `s < 32` and in `hi` otherwise.
///
/// A record is used rather than BigInt or fixnum's Int64 because it is the
/// only option that remains const-constructible, which this class needs for
/// its thirteen constant bitboards.
///
/// Every arithmetic result is normalised with `toUnsigned(32)`: that is
/// well-defined on both platforms, unlike raw shifts, which JavaScript
/// truncates to 32 bits and treats as signed.
extension type const SquareSet._((int, int) value) {
  /// Creates a [SquareSet] from a value that fits in 32 bits.
  const SquareSet(int lo) : value = (lo, 0);

  /// Creates a [SquareSet] from two 32-bit halves.
  const SquareSet.fromHiLo(int hi, int lo) : value = (lo, hi);

  /// Creates a [SquareSet] with a single [Square].
  const SquareSet.fromSquare(Square square)
      : value = square < 32 ? (1 << square, 0) : (0, 1 << (square - 32));

  /// Creates a [SquareSet] from several [Square]s.
  SquareSet.fromSquares(Iterable<Square> squares)
      : value = squares.fold((0, 0), (acc, square) {
          final s = SquareSet.fromSquare(square);
          return (acc.$1 | s._lo, acc.$2 | s._hi);
        });

  /// Create a [SquareSet] containing all squares of the given rank.
  const SquareSet.fromRank(Rank rank)
      : value = rank < 4 ? (0xff << (8 * rank), 0) : (0, 0xff << (8 * rank - 32)),
        assert(rank >= 0 && rank < 8);

  /// Create a [SquareSet] containing all squares of the given file.
  // the file mask repeats every 8 bits, so both halves are the same
  const SquareSet.fromFile(File file)
      : value = (0x01010101 << file, 0x01010101 << file),
        assert(file >= 0 && file < 8);

  /// Create a [SquareSet] containing all squares of the given backrank [Side].
  const SquareSet.backrankOf(Side side)
      : value = side == Side.white ? (0xff, 0) : (0, 0xff000000);

  int get _lo => value.$1;
  int get _hi => value.$2;

  static const empty = SquareSet.fromHiLo(0, 0);
  static const full = SquareSet.fromHiLo(0xffffffff, 0xffffffff);
  static const lightSquares = SquareSet.fromHiLo(0x55AA55AA, 0x55AA55AA);
  static const darkSquares = SquareSet.fromHiLo(0xAA55AA55, 0xAA55AA55);
  static const diagonal = SquareSet.fromHiLo(0x80402010, 0x08040201);
  static const antidiagonal = SquareSet.fromHiLo(0x01020408, 0x10204080);
  static const corners = SquareSet.fromHiLo(0x81000000, 0x00000081);
  static const center = SquareSet.fromHiLo(0x00000018, 0x18000000);
  static const backranks = SquareSet.fromHiLo(0xff000000, 0x000000ff);
  static const firstRank = SquareSet.fromHiLo(0, 0xff);
  static const eighthRank = SquareSet.fromHiLo(0xff000000, 0);
  static const aFile = SquareSet.fromHiLo(0x01010101, 0x01010101);
  static const hFile = SquareSet.fromHiLo(0x80808080, 0x80808080);

  /// Bitwise right shift
  SquareSet shr(int shift) {
    if (shift >= 64) return SquareSet.empty;
    if (shift <= 0) return this;
    if (shift == 32) return SquareSet.fromHiLo(0, _hi);
    if (shift > 32) return SquareSet.fromHiLo(0, (_hi >>> (shift - 32)));
    return SquareSet.fromHiLo(
      _hi >>> shift,
      ((_lo >>> shift) | (_hi << (32 - shift))).toUnsigned(32),
    );
  }

  /// Bitwise left shift
  SquareSet shl(int shift) {
    if (shift >= 64) return SquareSet.empty;
    if (shift <= 0) return this;
    if (shift == 32) return SquareSet.fromHiLo(_lo, 0);
    if (shift > 32) {
      return SquareSet.fromHiLo((_lo << (shift - 32)).toUnsigned(32), 0);
    }
    return SquareSet.fromHiLo(
      ((_hi << shift) | (_lo >>> (32 - shift))).toUnsigned(32),
      (_lo << shift).toUnsigned(32),
    );
  }

  /// Returns a new [SquareSet] with a bitwise XOR of this set and [other].
  SquareSet xor(SquareSet other) =>
      SquareSet.fromHiLo(_hi ^ other._hi, _lo ^ other._lo);
  SquareSet operator ^(SquareSet other) => xor(other);

  /// Returns a new [SquareSet] with the squares that are in either this set or [other].
  SquareSet union(SquareSet other) =>
      SquareSet.fromHiLo(_hi | other._hi, _lo | other._lo);
  SquareSet operator |(SquareSet other) => union(other);

  /// Returns a new [SquareSet] with the squares that are in both this set and [other].
  SquareSet intersect(SquareSet other) =>
      SquareSet.fromHiLo(_hi & other._hi, _lo & other._lo);
  SquareSet operator &(SquareSet other) => intersect(other);

  /// Returns a new [SquareSet] with the [other] squares removed from this set.
  // 64-bit subtraction, borrowing across the halves
  SquareSet minus(SquareSet other) {
    final lo = _lo - other._lo;
    final borrow = lo < 0 ? 1 : 0;
    return SquareSet.fromHiLo(
      (_hi - other._hi - borrow).toUnsigned(32),
      lo.toUnsigned(32),
    );
  }

  SquareSet operator -(SquareSet other) => minus(other);

  /// Returns the set complement of this set.
  SquareSet complement() =>
      SquareSet.fromHiLo((~_hi).toUnsigned(32), (~_lo).toUnsigned(32));

  /// Returns the set difference of this set and [other].
  SquareSet diff(SquareSet other) => SquareSet.fromHiLo(
      _hi & (~other._hi).toUnsigned(32), _lo & (~other._lo).toUnsigned(32));

  /// Flips the set vertically.
  SquareSet flipVertical() {
    const k1 = 0x00FF00FF;
    const k2 = 0x0000FFFF;
    int flipHalf(int x) {
      int r = ((x >>> 8) & k1) | ((x & k1) << 8).toUnsigned(32);
      r = ((r >>> 16) & k2) | ((r & k2) << 16).toUnsigned(32);
      return r;
    }

    // swapping the halves performs the final 32-bit rotation
    return SquareSet.fromHiLo(flipHalf(_lo), flipHalf(_hi));
  }

  /// Flips the set horizontally.
  SquareSet mirrorHorizontal() {
    const k1 = 0x55555555;
    const k2 = 0x33333333;
    const k4 = 0x0f0f0f0f;
    int mirrorHalf(int x) {
      int r = ((x >>> 1) & k1) | ((x & k1) << 1).toUnsigned(32);
      r = ((r >>> 2) & k2) | ((r & k2) << 2).toUnsigned(32);
      r = ((r >>> 4) & k4) | ((r & k4) << 4).toUnsigned(32);
      return r;
    }

    return SquareSet.fromHiLo(mirrorHalf(_hi), mirrorHalf(_lo));
  }

  /// Returns the number of squares in the set.
  int get size => _popcnt32(_lo) + _popcnt32(_hi);

  /// Returns true if the set is empty.
  bool get isEmpty => _lo == 0 && _hi == 0;

  /// Returns true if the set is not empty.
  bool get isNotEmpty => _lo != 0 || _hi != 0;

  /// Returns the first square in the set, or null if the set is empty.
  Square? get first =>
      _lo != 0 ? Square(_ntz32(_lo)) : (_hi != 0 ? Square(32 + _ntz32(_hi)) : null);

  /// Returns the last square in the set, or null if the set is empty.
  Square? get last => _hi != 0
      ? Square(63 - _nlz32(_hi))
      : (_lo != 0 ? Square(31 - _nlz32(_lo)) : null);

  /// Returns the squares in the set as an iterable.
  Iterable<Square> get squares => _iterateSquares();

  /// Returns the squares in the set as an iterable in reverse order.
  Iterable<Square> get squaresReversed => _iterateSquaresReversed();

  /// Returns true if the set contains more than one square.
  bool get moreThanOne => isNotEmpty && size > 1;

  /// Returns square if it is single, otherwise returns null.
  Square? get singleSquare => moreThanOne ? null : last;

  /// Returns true if the [SquareSet] contains the given [square].
  bool has(Square square) => square < 32
      ? _lo & (1 << square) != 0
      : _hi & (1 << (square - 32)) != 0;

  /// Returns true if the square set has any square in the [other] square set.
  bool isIntersected(SquareSet other) => intersect(other).isNotEmpty;

  /// Returns true if the square set is disjoint from the [other] square set.
  bool isDisjoint(SquareSet other) => intersect(other).isEmpty;

  /// Returns a new [SquareSet] with the given [square] added.
  SquareSet withSquare(Square square) => union(SquareSet.fromSquare(square));

  /// Returns a new [SquareSet] with the given [square] removed.
  SquareSet withoutSquare(Square square) => diff(SquareSet.fromSquare(square));

  /// Removes [Square] if present, or put it if absent.
  SquareSet toggleSquare(Square square) => xor(SquareSet.fromSquare(square));

  /// Returns a new [SquareSet] with its first [Square] removed.
  SquareSet withoutFirst() {
    final f = first;
    return f != null ? withoutSquare(f) : empty;
  }

  /// Returns the hexadecimal string representation of the bitboard value.
  String toHexString() {
    final hi = _hi.toRadixString(16).toUpperCase().padLeft(8, '0');
    final lo = _lo.toRadixString(16).toUpperCase().padLeft(8, '0');
    if (hi == '00000000' && lo == '00000000') return '0';
    return '0x$hi$lo';
  }

  Iterable<Square> _iterateSquares() sync* {
    SquareSet bitboard = this;
    while (bitboard.isNotEmpty) {
      final square = bitboard.first!;
      bitboard = bitboard.withoutSquare(square);
      yield square;
    }
  }

  Iterable<Square> _iterateSquaresReversed() sync* {
    SquareSet bitboard = this;
    while (bitboard.isNotEmpty) {
      final square = bitboard.last!;
      bitboard = bitboard.withoutSquare(square);
      yield square;
    }
  }
}

int _popcnt32(int n) {
  final count2 = n - ((n >>> 1) & 0x55555555);
  final count4 = (count2 & 0x33333333) + ((count2 >>> 2) & 0x33333333);
  final count8 = (count4 + (count4 >>> 4)) & 0x0f0f0f0f;
  // the native version multiplies by 0x0101010101010101; on web the
  // equivalent 32-bit multiply can exceed 2^32, so sum the bytes directly
  return (count8 + (count8 >>> 8) + (count8 >>> 16) + (count8 >>> 24)) & 0x3f;
}

/// Number of leading zeros in a 32-bit value.
int _nlz32(int x) {
  int r = x;
  r |= r >>> 1;
  r |= r >>> 2;
  r |= r >>> 4;
  r |= r >>> 8;
  r |= r >>> 16;
  return 32 - _popcnt32(r);
}

/// Number of trailing zeros in a 32-bit value; 32 when empty.
int _ntz32(int x) => x == 0 ? 32 : _popcnt32((x & -x) - 1);
