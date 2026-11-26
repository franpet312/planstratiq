import 'plan.dart';

/// Stavka popisa za kupnju (isti proizvod iste boje i mjera zbraja se u količinu).
class ShopLine {
  ShopLine(this.name, this.store, this.w, this.d, this.h, this.price, this.url);
  final String name;
  final String store;
  final double w, d, h;
  final double? price;
  final String? url;
  int qty = 1;
  double get total => (price ?? 0) * qty;
}

const genericStore = 'Planstratiq katalog (okvirne cijene)';

/// Popis za kupnju po trgovinama, za cijelu kuću (sve etaže). Trgovine idu abecedno, generički katalog zadnji.
Map<String, List<ShopLine>> shoppingList(Plan plan) {
  final byKey = <String, ShopLine>{};
  for (final l in plan.levels) {
    for (final it in l.items) {
      final store = it.retailer ?? genericStore;
      final key = '$store|${it.catalogId}|${it.name}|${it.color}|${it.w}|${it.d}|${it.h}';
      final e = byKey[key];
      if (e != null) {
        e.qty++;
      } else {
        byKey[key] = ShopLine(it.name, store, it.w, it.d, it.h, it.price, it.productUrl);
      }
    }
  }
  final out = <String, List<ShopLine>>{};
  for (final line in byKey.values) {
    (out[line.store] ??= []).add(line);
  }
  final keys = out.keys.toList()
    ..sort((a, b) {
      if (a == genericStore) return 1;
      if (b == genericStore) return -1;
      return a.compareTo(b);
    });
  return {for (final k in keys) k: out[k]!..sort((a, b) => b.total.compareTo(a.total))};
}

/// Popis za kupnju kao CSV (Excel), s poveznicama na proizvode.
String shoppingCsv(Plan plan) {
  final b = StringBuffer('﻿');
  String q(String s) => '"${s.replaceAll('"', '""')}"';
  String n(double v) => v.toStringAsFixed(2).replaceAll('.', ',');
  b.writeln('${q('Popis za kupnju')};${q(plan.name)}');
  var all = 0.0;
  for (final e in shoppingList(plan).entries) {
    b.writeln();
    b.writeln('${q(e.key)};${q('Kom')};${q('Mjere (cm)')};${q('Cijena (€)')};${q('Ukupno (€)')};${q('Poveznica')}');
    var sum = 0.0;
    for (final l in e.value) {
      sum += l.total;
      b.writeln('${q(l.name)};${l.qty};${q('${(l.w * 100).round()}×${(l.d * 100).round()}×${(l.h * 100).round()}')};'
          '${l.price == null ? '' : n(l.price!)};${n(l.total)};${q(l.url ?? '')}');
    }
    all += sum;
    b.writeln('${q('Ukupno ${e.key}')};;;;${n(sum)};');
  }
  b.writeln();
  b.writeln('${q('Sveukupno')};;;;${n(all)};');
  return b.toString();
}
