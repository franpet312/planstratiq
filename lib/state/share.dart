import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/plan.dart';

@JS('psqShare.pack')
external JSPromise<JSString> _pack(String s);

@JS('psqShare.unpack')
external JSPromise<JSString> _unpack(String s);

@JS('psqShare.pending')
external String? get _pending;

@JS('psqShare.pending')
external set _pending(String? v);

/// Poveznica koja sadrži cijeli projekt (bez slike nacrta), sažet u adresu.
Future<String> shareLink(Plan plan) async {
  final json = jsonEncode(plan.toJson(includeImage: false));
  final data = (await _pack(json).toDart).toDart;
  final loc = web.window.location;
  return '${loc.origin}${loc.pathname}#p=$data';
}

/// Ako je stranica otvorena podijeljenom poveznicom, vrati projekt i očisti adresu.
Future<Plan?> planFromLocation() async {
  final data = _pending;
  if (data == null || data.isEmpty) return null;
  _pending = null;
  try {
    final json = (await _unpack(data).toDart).toDart;
    return Plan.fromJson(jsonDecode(json) as Map<String, dynamic>);
  } catch (_) {
    return null;
  }
}
