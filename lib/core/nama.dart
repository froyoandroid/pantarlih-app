const _gelar = <String>{
  'h',
  'hj',
  'alm',
  'almh',
  'drs',
  'dra',
  'ir',
  'st',
  'spd',
  'mpd',
  'se',
  'ny',
  'tn',
  'bp',
  'bpk',
  'kh',
  'ust',
  'ustd',
};

const _digraf = <String, String>{
  'kh': 'h',
  'dz': 'z',
  'ts': 's',
  'sy': 's',
  'ch': 'h',
  'dj': 'j',
  'tj': 'c',
  'oe': 'u',
};
const _huruf = <String, String>{'y': 'i', 'q': 'k', 'f': 'p', 'v': 'p'};

String normalisasiNama(String input) {
  var s = input.toLowerCase().replaceAll(RegExp(r'[^a-z\s]'), ' ');
  var tokens = s
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty && !_gelar.contains(t))
      .toList();
  tokens = tokens
      .map((token) {
        var x = token;
        _digraf.forEach((a, b) => x = x.replaceAll(a, b));
        _huruf.forEach((a, b) => x = x.replaceAll(a, b));
        return x.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m.group(1)!);
      })
      .where((t) => t.isNotEmpty)
      .toList();
  return tokens.join(' ');
}

List<String> tokenNama(String input) =>
    normalisasiNama(input).split(' ').where((t) => t.isNotEmpty).toList();

int levenshtein(String a, String b, {int? maxDistance}) {
  if (a == b) return 0;
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  for (var i = 0; i < a.length; i++) {
    final current = <int>[i + 1];
    for (var j = 0; j < b.length; j++) {
      current.add([
        current[j] + 1,
        previous[j + 1] + 1,
        previous[j] + (a[i] == b[j] ? 0 : 1),
      ].reduce((x, y) => x < y ? x : y));
    }
    // Bail out once the distance provably exceeds the budget; callers only
    // care whether the pair is close, and full rows are wasted work then.
    if (maxDistance != null &&
        current.reduce((x, y) => x < y ? x : y) > maxDistance) {
      return maxDistance + 1;
    }
    previous = current;
  }
  return previous.last;
}

double _simToken(String a, String b) {
  if (a == b) return 1;
  if (a.startsWith(b) || b.startsWith(a)) {
    return 0.9 *
        (a.length < b.length ? a.length : b.length) /
        (a.length > b.length ? a.length : b.length);
  }
  final m = a.length > b.length ? a.length : b.length;
  if (m == 0) return 0;
  // 0.3 is the lowest similarity that can still matter to skorNama: anything
  // further is skipped without running the full edit-distance table.
  const batas = 0.3;
  final maksEdit = (m * (1 - batas)).floor();
  final lev = levenshtein(a, b, maxDistance: maksEdit);
  if (lev > maksEdit) return 0;
  return 1 - lev / m;
}

double skorNama(String query, String kandidat) {
  final q = tokenNama(query), k = tokenNama(kandidat);
  if (q.isEmpty || k.isEmpty) return 0;
  var weight = 0.0, value = 0.0;
  for (final qt in q) {
    var best = 0.0;
    for (final kt in k) {
      final score = _simToken(qt, kt);
      if (score > best) best = score;
    }
    weight += qt.length;
    value += best * qt.length;
  }
  var score = value / weight * 100;
  final difference = (q.length - k.length).abs();
  if (difference > 1) score -= (difference - 1) * 5;
  return score.clamp(0, 100).toDouble();
}
