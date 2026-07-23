import 'package:botvinnik_mobile/engine/engine_reaper.dart';
import 'package:flutter_test/flutter_test.dart';

// The engines dir a `ps` line would show for our binaries.
const _dir =
    '/Users/x/Library/Application Support/app.botvinnik.botvinnikMobile/engines';

void main() {
  test('flags orphaned engines (ppid 1, under the engines dir) and nothing else',
      () {
    final ps = [
      '  501     1 $_dir/velvet', // orphan of ours → kill
      '  502   999 $_dir/rodent go infinite', // parent alive → keep
      '  503     1 /usr/bin/coreaudiod', // orphan, not ours → keep
      '    1     0 /sbin/launchd', // launchd itself → keep
      '   42     1 $_dir/patricia --uci', // orphan of ours → kill
      '  888     1 /bin/bash -c tail -f $_dir/velvet.log', // only REFERENCES the dir → keep
    ].join('\n');
    expect(orphanEnginePids(ps, _dir, 999), unorderedEquals([501, 42]));
  });

  test('never targets our own process', () {
    expect(orphanEnginePids('  777     1 $_dir/velvet', _dir, 777), isEmpty);
  });

  test('tolerates blank and non-numeric lines', () {
    expect(orphanEnginePids('\nPID PPID COMMAND\n   junk', _dir, 1), isEmpty);
  });
}
