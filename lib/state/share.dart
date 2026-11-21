import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/plan.dart';

@JS('psqShare.pack')
external JSPromise<JSString> _pack(String s);

@JS('psqShare.unpack')
external JSPromise<JSString> _unpack(String s);

/// Poveznica koja sadrži cijeli projekt (bez slike nacrta), sažet u adresu.
Future<String> shareLink(Plan plan) async {
  final json = jsonEncode(plan.toJson(includeImage: false));
  final data = (await _pack(json).toDart).toDart;
  final loc = web.window.location;
  return '${loc.origin}${loc.pathname}#p=$data';
}

/// Ako je stranica otvorena podijeljenom poveznicom, vrati projekt i očisti adresu.
Future<Plan?> planFromLocation() async {
  final hash = web.window.location.hash;
  if (!hash.startsWith('#p=')) return null;
  try {
    final json = (await _unpack(hash.substring(3)).toDart).toDart;
    final plan = Plan.fromJson(jsonDecode(json) as Map<String, dynamic>);
    web.window.history.replaceState(null, '', web.window.location.pathname);
    return plan;
  } catch (_) {
    web.window.history.replaceState(null, '', web.window.location.pathname);
    return null;
  }
}
