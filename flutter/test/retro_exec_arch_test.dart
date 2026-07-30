// The macOS app is built universal (`ARCHS = arm64 x86_64`) but
// `stage-macos-engines.sh` runs a bare `go build`, which produces a binary for
// whatever arch the developer happened to be on. Before this check, `supported`
// asked only whether the file existed — so on an Intel Mac all three retro
// personas appeared in the picker and every single game was quietly played by
// Stockfish standing in, because the spawn failed with `Bad CPU type in
// executable` and a failed spawn is contractually just a null move.
//
// Every case passes an explicit host, so the suite asserts the same thing on
// the Linux CI runner as on a Mac. A version that read `Abi.current()` would
// pass vacuously in CI, which is how a suite here went silently macOS-only
// before.
import 'dart:io';
import 'dart:typed_data';

import 'package:botvinnik_mobile/engine/retro_engine.dart';
import 'package:flutter_test/flutter_test.dart';

const cpuX8664 = 0x01000007;
const cpuArm64 = 0x0100000C;

/// A minimal thin 64-bit Mach-O header: magic then cputype, little-endian.
Uint8List thin(int cpuType) {
  final b = BytesBuilder();
  final head = ByteData(8)
    ..setUint32(0, 0xFEEDFACF, Endian.little)
    ..setUint32(4, cpuType, Endian.little);
  b.add(head.buffer.asUint8List());
  b.add(Uint8List(64)); // the rest of a header we do not read
  return b.toBytes();
}

/// A fat header listing [cpuTypes] — big-endian, 20-byte `fat_arch` entries.
Uint8List fat(List<int> cpuTypes) {
  final bd = ByteData(8 + cpuTypes.length * 20)
    ..setUint32(0, 0xCAFEBABE, Endian.big)
    ..setUint32(4, cpuTypes.length, Endian.big);
  for (var i = 0; i < cpuTypes.length; i++) {
    bd.setUint32(8 + i * 20, cpuTypes[i], Endian.big);
  }
  return bd.buffer.asUint8List();
}

void main() {
  late Directory tmp;
  setUp(() => tmp = Directory.systemTemp.createTempSync('retro-arch'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String name, Uint8List bytes) =>
      File('${tmp.path}/$name')..writeAsBytesSync(bytes);

  test('a thin binary is loadable only on its own arch', () {
    final armBinary = write('arm', thin(cpuArm64));
    expect(RetroEngine.machOMatchesHost(armBinary, hostCpuType: cpuArm64), isTrue);
    // the regression: this is the Intel Mac, and it must NOT be offered
    expect(RetroEngine.machOMatchesHost(armBinary, hostCpuType: cpuX8664), isFalse);

    final intelBinary = write('intel', thin(cpuX8664));
    expect(RetroEngine.machOMatchesHost(intelBinary, hostCpuType: cpuX8664), isTrue);
    expect(RetroEngine.machOMatchesHost(intelBinary, hostCpuType: cpuArm64), isFalse);
  });

  test('a universal binary is loadable on both, which is the fix we did not take', () {
    final universal = write('fat', fat([cpuX8664, cpuArm64]));
    expect(RetroEngine.machOMatchesHost(universal, hostCpuType: cpuArm64), isTrue);
    expect(RetroEngine.machOMatchesHost(universal, hostCpuType: cpuX8664), isTrue);
  });

  test('a fat binary missing the host slice is rejected', () {
    final armOnlyFat = write('fat1', fat([cpuArm64]));
    expect(RetroEngine.machOMatchesHost(armOnlyFat, hostCpuType: cpuX8664), isFalse);
  });

  test('anything that is not a Mach-O is not executable', () {
    expect(
      RetroEngine.machOMatchesHost(
        write('text', Uint8List.fromList('#!/bin/sh\necho hi\n'.codeUnits)),
        hostCpuType: cpuArm64,
      ),
      isFalse,
    );
    // truncated below the header we need to read
    expect(
      RetroEngine.machOMatchesHost(write('tiny', Uint8List(4)), hostCpuType: cpuArm64),
      isFalse,
    );
    expect(
      RetroEngine.machOMatchesHost(File('${tmp.path}/does-not-exist'), hostCpuType: cpuArm64),
      isFalse,
    );
  });

  test('an unrecognised host does not hide retro', () {
    // Linux, Windows, anything without a macOS ABI: fall back to the old
    // behaviour rather than blocking on a guess about a platform we have not
    // reasoned about.
    final armBinary = write('arm', thin(cpuArm64));
    expect(RetroEngine.machOMatchesHost(armBinary, hostCpuType: null), isTrue);
  }, skip: Platform.isMacOS ? 'hostCpuType: null resolves to the real host on a Mac' : false);

  test('the actually staged binary matches this machine', () {
    // Only meaningful where someone has run stage-macos-engines.sh. Skipping in
    // CI is honest — CI never builds these — but on a developer Mac this is the
    // one case that reads real bytes rather than a header this test wrote.
    final staged = File('macos/Runner/Resources/retro/turochamp');
    if (!staged.existsSync()) {
      markTestSkipped('no staged retro binary; run ./stage-macos-engines.sh');
      return;
    }
    expect(RetroEngine.machOMatchesHost(staged), isTrue);
  });
}
