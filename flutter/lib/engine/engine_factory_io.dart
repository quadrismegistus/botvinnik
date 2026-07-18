// Picks the engine transport for the platform: embedded FFI Stockfish on
// mobile, a child engine process on desktop. Everything downstream (the
// arbiter, and therefore all of the app) sees only UciSearcher.

import 'dart:io';

import 'process_engine.dart';
import 'search_engine.dart';

Future<UciSearcher> startEngine() async {
  if (Platform.isIOS || Platform.isAndroid) return SearchEngine.start();
  return ProcessEngine.start();
}
