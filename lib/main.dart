import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart'; // dibuat otomatis oleh `flutterfire configure`

/// Alamat web (GitHub Pages) untuk link share saat tombol share ditekan dari apk.
/// GANTI sesuai akun GitHub dan nama repo-mu.
const String kShareBase = 'https://Alexiaa15.github.io/bracket-arena/';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const BracketApp());
}

// ============================================================
// WARNA & HELPER
// ============================================================

const kBg1 = Color(0xFF0E1128);
const kBg2 = Color(0xFF1A1040);
const kAccent = Color(0xFF7C5CFF);
const kTeal = Color(0xFF19E3C2);
const kGold = Color(0xFFFFC857);
const kCard = Color(0xFF1B1745);

Color alpha(Color c, double o) =>
    c.withAlpha((o * 255).round().clamp(0, 255).toInt());

Color teamColor(int id) =>
    HSLColor.fromAHSL(1, (id * 137.508) % 360, 0.62, 0.55).toColor();

String initialOf(String name) {
  final n = name.trim();
  return n.isEmpty ? '?' : n.characters.first.toUpperCase();
}

String roundName(int r, int total, int matches) {
  final fromEnd = total - 1 - r;
  if (fromEnd == 0) return 'Final';
  if (fromEnd == 1) return 'Semifinal';
  if (fromEnd == 2 && matches == 4) return 'Perempat Final';
  return 'Ronde ${r + 1}';
}

Route<T> fadeSlide<T>(Widget page, {String? name}) => PageRouteBuilder<T>(
      settings: RouteSettings(name: name),
      transitionDuration: const Duration(milliseconds: 450),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, a, __, child) {
        final curved = CurvedAnimation(parent: a, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
                .animate(curved),
            child: child,
          ),
        );
      },
    );

// ============================================================
// APP
// ============================================================

class BracketApp extends StatelessWidget {
  const BracketApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bracket Arena',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: kAccent,
        scaffoldBackgroundColor: kBg1,
      ),
      onGenerateInitialRoutes: (name) => [appRoute(RouteSettings(name: name))],
      onGenerateRoute: appRoute,
    );
  }
}

// ============================================================
// MODEL (logika bracket)
// ============================================================

class MatchModel {
  int? a, b, winner; // id peserta
  int sa = 0, sb = 0;

  bool get played => winner != null;
  int? get loser => winner == null ? null : (winner == a ? b : a);

  void reset() {
    winner = null;
    sa = 0;
    sb = 0;
  }
}

class RoundModel {
  final List<MatchModel> matches;
  final bool hasBye;
  int? bye;
  RoundModel(int n, this.hasBye) : matches = List.generate(n, (_) => MatchModel());
}

class BoRule {
  /// null = skor tidak valid, -1 = seri (BO2 1-1, pemenang dipilih manual),
  /// 0 = A menang, 1 = B menang
  static int? decide(int bo, int sa, int sb) {
    if (bo == 1) {
      if (sa == 1 && sb == 0) return 0;
      if (sa == 0 && sb == 1) return 1;
      return null;
    }
    if (bo == 2) {
      if (sa == 2 && sb == 0) return 0;
      if (sa == 0 && sb == 2) return 1;
      if (sa == 1 && sb == 1) return -1;
      return null;
    }
    if (sa == 2 && sb < 2) return 0;
    if (sb == 2 && sa < 2) return 1;
    return null;
  }
}

class Tournament {
  final List<String> names;
  final List<int> order;
  final int bestOf;
  final bool thirdPlace;
  final List<RoundModel> rounds = [];
  final MatchModel third = MatchModel();
  late final bool hasThird;

  Tournament({
    required this.names,
    required this.order,
    required this.bestOf,
    required this.thirdPlace,
  }) {
    var c = order.length;
    while (c > 1) {
      final m = c ~/ 2;
      rounds.add(RoundModel(m, c.isOdd));
      c = m + (c.isOdd ? 1 : 0);
    }
    hasThird = thirdPlace &&
        rounds.length >= 2 &&
        rounds[rounds.length - 2].matches.length == 2;
    propagate();
  }

  static bool thirdAvailable(int n) {
    final counts = <int>[];
    var c = n;
    while (c > 1) {
      final m = c ~/ 2;
      counts.add(m);
      c = m + (c.isOdd ? 1 : 0);
    }
    return counts.length >= 2 && counts[counts.length - 2] == 2;
  }

  static List<String> preview(int n) {
    final counts = <int>[];
    final byes = <bool>[];
    var c = n;
    while (c > 1) {
      final m = c ~/ 2;
      counts.add(m);
      byes.add(c.isOdd);
      c = m + (c.isOdd ? 1 : 0);
    }
    return [
      for (var r = 0; r < counts.length; r++)
        '${roundName(r, counts.length, counts[r])} · ${counts[r]}${byes[r] ? ' +BYE' : ''}',
    ];
  }

  int? get champion => rounds.last.matches[0].winner;
  int? get runnerUp => rounds.last.matches[0].loser;
  int? get thirdWinner => hasThird ? third.winner : null;

  int get totalMatches =>
      rounds.fold<int>(0, (s, r) => s + r.matches.length) + (hasThird ? 1 : 0);
  int get doneMatches =>
      rounds.fold<int>(0, (s, r) => s + r.matches.where((m) => m.played).length) +
      (hasThird && third.played ? 1 : 0);

  void propagate() {
    List<int?> entrants = List<int?>.from(order);
    for (final r in rounds) {
      final odd = entrants.length.isOdd;
      for (var i = 0; i < r.matches.length; i++) {
        final mt = r.matches[i];
        final na = entrants[2 * i];
        final nb = entrants[2 * i + 1];
        if (mt.a != na || mt.b != nb) {
          mt.a = na;
          mt.b = nb;
          mt.reset();
        }
      }
      r.bye = odd ? entrants.last : null;
      final carry = odd ? entrants.last : null;
      entrants = [
        for (final mt in r.matches) mt.winner,
        if (odd) carry,
      ];
    }
    if (hasThird) {
      final semi = rounds[rounds.length - 2];
      final na = semi.matches[0].loser;
      final nb = semi.matches[1].loser;
      if (third.a != na || third.b != nb) {
        third.a = na;
        third.b = nb;
        third.reset();
      }
    }
  }

  /// Hasil pertandingan -> Map untuk disimpan di Firestore.
  Map<String, dynamic> resultsMap() {
    final out = <String, dynamic>{};
    for (var r = 0; r < rounds.length; r++) {
      for (var i = 0; i < rounds[r].matches.length; i++) {
        final m = rounds[r].matches[i];
        if (m.played || m.sa > 0 || m.sb > 0) {
          out['${r}_$i'] = {'sa': m.sa, 'sb': m.sb, 'w': m.winner};
        }
      }
    }
    if (hasThird && (third.played || third.sa > 0 || third.sb > 0)) {
      out['third'] = {'sa': third.sa, 'sb': third.sb, 'w': third.winner};
    }
    return out;
  }

  void applyResults(Map<String, dynamic> res) {
    void apply(MatchModel m, dynamic raw) {
      if (raw is! Map || m.a == null || m.b == null) return;
      final w = (raw['w'] as num?)?.toInt();
      if (w != null && w != m.a && w != m.b) return;
      m.sa = (raw['sa'] as num?)?.toInt() ?? 0;
      m.sb = (raw['sb'] as num?)?.toInt() ?? 0;
      m.winner = w; // null = skor sementara (match belum selesai)
    }

    for (var r = 0; r < rounds.length; r++) {
      for (var i = 0; i < rounds[r].matches.length; i++) {
        apply(rounds[r].matches[i], res['${r}_$i']);
      }
      propagate();
    }
    if (hasThird) apply(third, res['third']);
  }

  static Tournament fromData(Map<String, dynamic> d) {
    final t = Tournament(
      names: List<String>.from(d['names'] as List),
      order: (d['order'] as List).map((e) => (e as num).toInt()).toList(),
      bestOf: (d['bestOf'] as num).toInt(),
      thirdPlace: d['thirdPlace'] == true,
    );
    t.applyResults(Map<String, dynamic>.from((d['results'] as Map?) ?? {}));
    return t;
  }

  void resetAll() {
    for (final r in rounds) {
      for (final m in r.matches) {
        m.reset();
      }
    }
    third.reset();
    propagate();
  }
}

// ============================================================
// WIDGET UMUM
// ============================================================

Widget _glow(Color c, double size, double o) => IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [alpha(c, o), alpha(c, 0)]),
        ),
      ),
    );

class GradientBg extends StatelessWidget {
  final Widget child;
  const GradientBg({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [kBg1, kBg2],
        ),
      ),
      child: Stack(
        children: [
          Positioned(top: -90, right: -70, child: _glow(kAccent, 300, 0.35)),
          Positioned(bottom: 80, left: -110, child: _glow(kTeal, 300, 0.10)),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

class Glass extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Glass({super.key, required this.child, this.padding = const EdgeInsets.all(18)});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: alpha(Colors.white, 0.07),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: alpha(Colors.white, 0.12)),
      ),
      child: child,
    );
  }
}

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  const _RoundBtn({required this.icon, required this.onTap, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.3 : 1,
      child: _Pressable(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: alpha(Colors.white, 0.1),
            border: Border.all(color: alpha(Colors.white, 0.18)),
          ),
          child: Icon(icon, color: Colors.white, size: size * 0.5),
        ),
      ),
    );
  }
}

class _GradientButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final List<Color> colors;
  const _GradientButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.colors = const [kAccent, Color(0xFF5B8CFF)],
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: _Pressable(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: colors),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: alpha(colors.first, 0.45),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  const _OptionTile({
    required this.selected,
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [kAccent, Color(0xFF5B8CFF)],
                )
              : null,
          color: selected ? null : alpha(Colors.white, 0.06),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? alpha(Colors.white, 0.5) : alpha(Colors.white, 0.12),
          ),
          boxShadow: selected
              ? [BoxShadow(color: alpha(kAccent, 0.4), blurRadius: 14)]
              : const <BoxShadow>[],
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 26),
            const SizedBox(height: 6),
            Text(title,
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
            Text(sub,
                textAlign: TextAlign.center,
                style: TextStyle(color: alpha(Colors.white, 0.65), fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// LOGO (sama dengan ikon aplikasi)
// ============================================================

class BracketLogo extends StatelessWidget {
  final double size;
  const BracketLogo({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 1024);
    const full = Rect.fromLTWH(0, 0, 1024, 1024);
    canvas.drawRRect(
      RRect.fromRectAndRadius(full, const Radius.circular(230)),
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8E74FF), Color(0xFF2B1573)],
        ).createShader(full),
    );

    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 44
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    final white = Path()
      ..moveTo(170, 270)..lineTo(340, 270)
      ..moveTo(170, 430)..lineTo(340, 430)
      ..moveTo(340, 270)..lineTo(340, 430)
      ..moveTo(170, 594)..lineTo(340, 594)
      ..moveTo(170, 754)..lineTo(340, 754)
      ..moveTo(340, 594)..lineTo(340, 754)
      ..moveTo(340, 350)..lineTo(520, 350)
      ..moveTo(340, 674)..lineTo(520, 674)
      ..moveTo(520, 350)..lineTo(520, 674)
      ..moveTo(520, 512)..lineTo(640, 512);
    canvas.drawPath(white, stroke(const Color(0xEBFFFFFF)));

    final teal = Path()
      ..moveTo(170, 270)
      ..lineTo(340, 270)
      ..lineTo(340, 350)
      ..lineTo(520, 350)
      ..lineTo(520, 512)
      ..lineTo(640, 512);
    canvas.drawPath(teal, stroke(kTeal));

    canvas.drawCircle(const Offset(740, 512), 100, Paint()..color = kGold);
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final ang = -pi / 2 + i * pi / 5;
      final rad = i.isEven ? 62.0 : 26.0;
      final p = Offset(740 + rad * cos(ang), 512 + rad * sin(ang));
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = const Color(0xFF2B1573));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ============================================================
// HALAMAN SETUP
// ============================================================

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  int _count = 8;
  bool _third = true;
  int _bo = 1;
  bool _shuffle = false;
  bool _saving = false;
  final _titleCtrl = TextEditingController();
  final List<TextEditingController> _ctrls = [];

  @override
  void initState() {
    super.initState();
    _setCount(8, notify: false);
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    for (final c in _ctrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _setCount(int n, {bool notify = true}) {
    final v = n.clamp(2, 64).toInt();
    while (_ctrls.length < v) {
      _ctrls.add(TextEditingController());
    }
    _count = v;
    if (notify) setState(() {});
  }

  Future<void> _start() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _saving) return;
    FocusScope.of(context).unfocus();
    HapticFeedback.mediumImpact();
    final names = [
      for (var i = 0; i < _count; i++)
        _ctrls[i].text.trim().isEmpty ? 'Peserta ${i + 1}' : _ctrls[i].text.trim(),
    ];
    final order = List<int>.generate(_count, (i) => i);
    if (_shuffle) order.shuffle(Random());
    final t = Tournament(
      names: names,
      order: order,
      bestOf: _bo,
      thirdPlace: _third,
    );
    final title = _titleCtrl.text.trim().isEmpty
        ? 'Turnamen $_count Peserta'
        : _titleCtrl.text.trim();

    setState(() => _saving = true);
    try {
      final id = await Repo.create(user: user, title: title, t: t);
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        fadeSlide(CloudBracketPage(id: id), name: '/b/$id'),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text('Gagal menyimpan bracket: $e'),
      ));
    }
  }

  Widget _title(IconData icon, String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Icon(icon, size: 20, color: kTeal),
            const SizedBox(width: 8),
            Text(text,
                style: const TextStyle(
                    color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
      );

  Widget _pill(String text, {bool selected = false}) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? kTeal : alpha(Colors.white, 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? kTeal : alpha(Colors.white, 0.14)),
        ),
        child: Text(text,
            style: TextStyle(
              color: selected ? kBg1 : alpha(Colors.white, 0.85),
              fontWeight: FontWeight.w700,
              fontSize: 12,
            )),
      );

  Widget _titleCard() {
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.emoji_events_outlined, 'Judul Turnamen'),
          TextField(
            controller: _titleCtrl,
            cursorColor: kTeal,
            maxLength: 50,
            style: const TextStyle(color: Colors.white),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              counterText: '',
              fillColor: alpha(Colors.white, 0.06),
              hintText: 'mis. Turnamen Gaple RT 05',
              hintStyle: TextStyle(color: alpha(Colors.white, 0.35)),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: kTeal, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _countCard() {
    final hasBye = _count.isOdd;
    return Glass(
      child: Column(
        children: [
          _title(Icons.groups_rounded, 'Jumlah Pemain / Tim'),
          Row(
            children: [
              _RoundBtn(
                icon: Icons.remove,
                onTap: _count > 2 ? () => _setCount(_count - 1) : null,
              ),
              Expanded(
                child: Column(
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (c, a) => ScaleTransition(
                        scale: a,
                        child: FadeTransition(opacity: a, child: c),
                      ),
                      child: Text(
                        '$_count',
                        key: ValueKey(_count),
                        style: const TextStyle(
                            fontSize: 56,
                            height: 1.1,
                            fontWeight: FontWeight.w800,
                            color: Colors.white),
                      ),
                    ),
                    Text('peserta',
                        style: TextStyle(color: alpha(Colors.white, 0.6))),
                  ],
                ),
              ),
              _RoundBtn(
                icon: Icons.add,
                onTap: _count < 64 ? () => _setCount(_count + 1) : null,
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: kTeal,
              inactiveTrackColor: alpha(Colors.white, 0.15),
              thumbColor: Colors.white,
              overlayColor: alpha(kTeal, 0.2),
              valueIndicatorColor: kAccent,
            ),
            child: Slider(
              value: _count.toDouble(),
              min: 2,
              max: 64,
              divisions: 62,
              label: '$_count',
              onChanged: (v) => _setCount(v.round()),
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final p in const [4, 6, 8, 12, 16, 32])
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _setCount(p);
                  },
                  child: _pill('$p', selected: _count == p),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: alpha(Colors.white, 0.1)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final l in Tournament.preview(_count)) _pill(l)],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(hasBye ? Icons.info_outline : Icons.check_circle_outline,
                  size: 16, color: hasBye ? kGold : kTeal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  hasBye
                      ? 'Jumlah ganjil: 1 peserta dapat BYE di ronde 1'
                      : 'Jumlah genap: semua langsung bertanding, tanpa BYE di ronde 1',
                  style: TextStyle(color: alpha(Colors.white, 0.7), fontSize: 12),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _settingsCard() {
    final thirdOk = Tournament.thirdAvailable(_count);
    const boSub = {1: 'Sekali main', 2: '2 game', 3: 'Menang 2'};
    const boIcon = {
      1: Icons.looks_one_rounded,
      2: Icons.looks_two_rounded,
      3: Icons.looks_3_rounded,
    };
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.sports_esports_rounded, 'Sistem Pertandingan'),
          Row(
            children: [
              for (final bo in const [1, 2, 3])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: _OptionTile(
                      selected: _bo == bo,
                      icon: boIcon[bo]!,
                      title: 'BO$bo',
                      sub: boSub[bo]!,
                      onTap: () => setState(() => _bo = bo),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _title(Icons.swap_vert_rounded, 'Penempatan Peserta'),
          Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _OptionTile(
                    selected: !_shuffle,
                    icon: Icons.format_list_numbered_rounded,
                    title: 'Berurutan',
                    sub: 'Sesuai daftar',
                    onTap: () => setState(() => _shuffle = false),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _OptionTile(
                    selected: _shuffle,
                    icon: Icons.shuffle_rounded,
                    title: 'Acak',
                    sub: 'Diundi random',
                    onTap: () => setState(() => _shuffle = true),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Divider(color: alpha(Colors.white, 0.1)),
          Row(
            children: [
              const Icon(Icons.workspace_premium_rounded, color: kGold),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Perebutan Juara 3',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15)),
              ),
              Switch(
                value: _third,
                onChanged: (v) {
                  HapticFeedback.selectionClick();
                  setState(() => _third = v);
                },
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
            child: (_third && !thirdOk)
                ? Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      'Juara 3 tidak tersedia untuk $_count peserta karena semifinal '
                      'tidak lengkap (ada BYE). Coba 4, 7, 8, 14, 16, dst.',
                      style: const TextStyle(color: Color(0xFFFF8A80), fontSize: 12),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _namesCard() {
    return Glass(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _title(Icons.edit_note_rounded, 'Nama Pemain / Tim'),
          Text('Kosongkan untuk nama otomatis',
              style: TextStyle(color: alpha(Colors.white, 0.55), fontSize: 12)),
          const SizedBox(height: 12),
          for (var i = 0; i < _count; i++)
            TweenAnimationBuilder<double>(
              key: ValueKey('field$i'),
              tween: Tween<double>(begin: 0.0, end: 1.0),
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              builder: (c, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(offset: Offset(0, (1 - v) * 12), child: child),
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _ctrls[i],
                  cursorColor: kTeal,
                  style: const TextStyle(color: Colors.white),
                  textInputAction:
                      i == _count - 1 ? TextInputAction.done : TextInputAction.next,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: alpha(Colors.white, 0.06),
                    hintText: 'Peserta ${i + 1}',
                    hintStyle: TextStyle(color: alpha(Colors.white, 0.35)),
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(8),
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: teamColor(i),
                        child: Text('${i + 1}',
                            style: const TextStyle(
                                fontSize: 12,
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: kTeal, width: 1.5),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  children: [
                    Row(
                      children: [
                        if (Navigator.canPop(context))
                          IconButton(
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back_rounded),
                          ),
                        const BracketLogo(size: 58),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Bracket Arena',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 0.5)),
                              Text('Atur turnamenmu, lalu mainkan!',
                                  style: TextStyle(color: alpha(Colors.white, 0.65))),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    _titleCard(),
                    const SizedBox(height: 14),
                    _countCard(),
                    const SizedBox(height: 14),
                    _settingsCard(),
                    const SizedBox(height: 14),
                    _namesCard(),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [alpha(kBg2, 0), kBg2],
                  ),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: _GradientButton(
                    label: _saving ? 'Menyimpan...' : 'Mulai Turnamen',
                    icon: Icons.play_arrow_rounded,
                    onTap: _saving ? null : _start,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// KARTU PERTANDINGAN
// ============================================================

class _MatchCard extends StatelessWidget {
  final MatchModel m;
  final List<String> names;
  final Animation<double> pulse;
  final VoidCallback onTap;
  final bool readOnly;
  const _MatchCard({
    required this.m,
    required this.names,
    required this.pulse,
    required this.onTap,
    this.readOnly = false,
  });

  bool get ready => !readOnly && m.a != null && m.b != null && !m.played;
  bool get inProgress => !m.played && (m.sa > 0 || m.sb > 0);

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: ready
          ? AnimatedBuilder(animation: pulse, builder: (_, __) => _body(pulse.value))
          : _body(0),
    );
  }

  Widget _body(double glow) {
    final border = ready
        ? alpha(inProgress ? kGold : kTeal, 0.45 + 0.5 * glow)
        : m.played
            ? alpha(kAccent, 0.8)
            : inProgress
                ? alpha(kGold, 0.7)
                : alpha(Colors.white, 0.12);
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: ready ? 2 : 1.5),
        boxShadow: ready
            ? [BoxShadow(color: alpha(inProgress ? kGold : kTeal, 0.12 + 0.25 * glow), blurRadius: 8 + 16 * glow)]
            : m.played
                ? [BoxShadow(color: alpha(kAccent, 0.3), blurRadius: 14)]
                : const <BoxShadow>[],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          children: [
            Expanded(child: _row(m.a, m.sa)),
            Container(height: 1, color: alpha(Colors.white, 0.08)),
            Expanded(child: _row(m.b, m.sb)),
          ],
        ),
      ),
    );
  }

  Widget _row(int? id, int score) {
    final win = id != null && m.winner == id;
    final lose = m.played && !win;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      color: win ? alpha(kAccent, 0.38) : Colors.transparent,
      child: Row(
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: id == null ? alpha(Colors.white, 0.12) : teamColor(id),
            child: Text(
              id == null ? '?' : initialOf(names[id]),
              style: const TextStyle(
                  fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              id == null ? 'Menunggu...' : names[id],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontStyle: id == null ? FontStyle.italic : FontStyle.normal,
                fontWeight: win ? FontWeight.w800 : FontWeight.w500,
                color: id == null
                    ? alpha(Colors.white, 0.35)
                    : lose
                        ? alpha(Colors.white, 0.45)
                        : Colors.white,
              ),
            ),
          ),
          if (m.played || inProgress)
            Text('$score',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: win ? kTeal : (inProgress ? kGold : alpha(Colors.white, 0.5)))),
          if (win)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.check_circle, size: 16, color: kTeal),
            ),
        ],
      ),
    );
  }
}

class _Link {
  final double x1, y1, x2, y2;
  final bool active;
  const _Link(this.x1, this.y1, this.x2, this.y2, this.active);
}

class _LinkPainter extends CustomPainter {
  final List<_Link> links;
  _LinkPainter(this.links);

  Path _path(_Link l) {
    final mid = (l.x1 + l.x2) / 2;
    return Path()
      ..moveTo(l.x1, l.y1)
      ..cubicTo(mid, l.y1, mid, l.y2, l.x2, l.y2);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final idle = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = alpha(Colors.white, 0.18);
    for (final l in links.where((l) => !l.active)) {
      canvas.drawPath(_path(l), idle);
    }
    final glowP = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..color = alpha(kTeal, 0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = kTeal;
    for (final l in links.where((l) => l.active)) {
      final p = _path(l);
      canvas.drawPath(p, glowP);
      canvas.drawPath(p, line);
    }
  }

  @override
  bool shouldRepaint(covariant _LinkPainter old) => true;
}

class _Geo {
  final List<List<double>> matchY = [];
  final List<double?> byeY = [];
  final List<List<double>> outY = [];
  final List<_Link> links = [];
  double width = 0, height = 0, finalY = 0;
}

// ============================================================
// HALAMAN BRACKET
// ============================================================

class _Res {
  final int sa, sb, side;
  final bool clear, finish;
  const _Res(this.sa, this.sb, this.side, {this.clear = false, this.finish = false});
}

class BracketPage extends StatefulWidget {
  final Tournament t;
  final String title;
  final bool readOnly;
  final String? ownerName;
  final String shareUrl;
  final Future<void> Function(Tournament t)? onSave;
  const BracketPage({
    super.key,
    required this.t,
    required this.title,
    required this.shareUrl,
    this.readOnly = false,
    this.ownerName,
    this.onSave,
  });

  @override
  State<BracketPage> createState() => _BracketPageState();
}

class _BracketPageState extends State<BracketPage> with TickerProviderStateMixin {
  Tournament get t => widget.t;

  static const double cardW = 210,
      cardH = 84,
      slot = 112,
      gapX = 70,
      topPad = 52,
      sidePad = 28,
      trophyW = 170;

  late final AnimationController _pulse;
  final TransformationController _tc = TransformationController();
  bool _fitted = false;
  Size _vp = Size.zero, _content = Size.zero;
  int? _celebrated;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _tc.dispose();
    super.dispose();
  }

  double _x(int r) => sidePad + r * (cardW + gapX);
  double _y(double v) => topPad + v;

  _Geo _geo() {
    final g = _Geo();
    List<double> prev = [];
    for (var r = 0; r < t.rounds.length; r++) {
      final rd = t.rounds[r];
      final my = <double>[];
      double? by;
      if (r == 0) {
        for (var i = 0; i < rd.matches.length; i++) {
          my.add((i + 0.5) * slot);
        }
        if (rd.hasBye) by = (rd.matches.length + 0.5) * slot;
      } else {
        for (var i = 0; i < rd.matches.length; i++) {
          my.add((prev[2 * i] + prev[2 * i + 1]) / 2);
        }
        if (rd.hasBye) by = prev.last;
      }
      g.matchY.add(my);
      g.byeY.add(by);
      prev = [...my, if (by != null) by];
      g.outY.add(prev);
    }

    // konektor antar ronde
    for (var r = 1; r < t.rounds.length; r++) {
      final prevR = t.rounds[r - 1];
      final prevOut = g.outY[r - 1];
      for (var k = 0; k < prevOut.length; k++) {
        final isLast = k == prevOut.length - 1;
        final isByeSrc = prevR.hasBye && isLast;
        final active = isByeSrc ? prevR.bye != null : prevR.matches[k].winner != null;
        final destBye = t.rounds[r].hasBye && isLast;
        final dy = destBye ? g.byeY[r]! : g.matchY[r][k ~/ 2];
        g.links.add(_Link(_x(r - 1) + cardW, _y(prevOut[k]), _x(r), _y(dy), active));
      }
    }

    final R = t.rounds.length;
    g.finalY = g.matchY.last[0];
    // konektor final -> piala
    g.links.add(_Link(_x(R - 1) + cardW, _y(g.finalY), _x(R), _y(g.finalY),
        t.champion != null));

    final maxV = g.outY.expand((e) => e).reduce(max);
    g.width = sidePad * 2 + R * (cardW + gapX) + trophyW;
    var h = topPad + maxV + slot / 2 + 24;
    if (t.hasThird) {
      h = max(h, _y(g.finalY + slot * 1.3) + cardH / 2 + 24);
    }
    g.height = h;
    return g;
  }

  void _fit() {
    if (_vp.isEmpty || _content.isEmpty) return;
    final s = max(0.4, min(1.0, _vp.width / _content.width));
    final dx = max(0.0, (_vp.width - _content.width * s) / 2);
    final dy = max(0.0, (_vp.height - _content.height * s) / 2);
    final m = Matrix4.diagonal3Values(s, s, 1.0);
    m.setTranslationRaw(dx, dy, 0.0);
    _tc.value = m;
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(msg),
      ));
  }

  Future<void> _save() async {
    final cb = widget.onSave;
    if (cb == null) return;
    try {
      await cb(t);
    } catch (e) {
      if (mounted) _snack('Gagal menyimpan: $e');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(ClipboardData(text: widget.shareUrl));
    if (mounted) _snack('Link disalin. Kirim ke temanmu untuk melihat progres.');
  }

  /// Posisi pertandingan di turnamen saat ini: [ronde, indeks], ronde -2 = juara 3.
  List<int>? _locate(MatchModel m) {
    if (identical(m, t.third)) return [-2, 0];
    for (var r = 0; r < t.rounds.length; r++) {
      for (var i = 0; i < t.rounds[r].matches.length; i++) {
        if (identical(t.rounds[r].matches[i], m)) return [r, i];
      }
    }
    return null;
  }

  Future<void> _edit(MatchModel m, String title) async {
    if (widget.readOnly) {
      HapticFeedback.lightImpact();
      _snack('Mode lihat saja. Hanya pembuat bracket yang bisa mengisi skor.');
      return;
    }
    if (m.a == null || m.b == null) {
      HapticFeedback.lightImpact();
      _snack('Lawan belum ditentukan, selesaikan ronde sebelumnya dulu.');
      return;
    }
    final loc = _locate(m);
    if (loc == null) return;
    final a0 = m.a, b0 = m.b;
    HapticFeedback.selectionClick();
    final res = await showModalBottomSheet<_Res>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScoreSheet(t: t, m: m, title: title),
    );
    if (res == null || !mounted) return;

    // ambil pertandingan yang sama dari data terbaru (bisa berubah saat sheet terbuka)
    final cur = loc[0] == -2 ? t.third : t.rounds[loc[0]].matches[loc[1]];
    if (cur.a != a0 || cur.b != b0) {
      _snack('Data bracket berubah, coba isi ulang skornya.');
      return;
    }
    setState(() {
      if (res.clear) {
        cur.reset();
      } else {
        cur.sa = res.sa;
        cur.sb = res.sb;
        cur.winner = res.finish ? (res.side == 0 ? cur.a : cur.b) : null;
      }
      t.propagate();
    });
    _save();
    HapticFeedback.mediumImpact();

    final champ = t.champion;
    if (champ == null) {
      _celebrated = null;
    } else if (_celebrated != champ) {
      _celebrated = champ;
      await Future<void>.delayed(const Duration(milliseconds: 350));
      if (mounted) _celebrate();
    }
  }

  Future<void> _celebrate() {
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Tutup',
      barrierColor: alpha(Colors.black, 0.75),
      transitionDuration: const Duration(milliseconds: 400),
      pageBuilder: (_, __, ___) => _Celebration(t: t),
      transitionBuilder: (_, a, __, child) => FadeTransition(
        opacity: a,
        child: ScaleTransition(
          scale: CurvedAnimation(parent: a, curve: Curves.easeOutBack),
          child: child,
        ),
      ),
    );
  }

  // ---------- potongan UI ----------

  Widget _viewerBanner() {
    const red = Color(0xFFFF5252);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: alpha(Colors.white, 0.07),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: alpha(Colors.white, 0.12)),
      ),
      child: Row(
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: red,
                boxShadow: [
                  BoxShadow(
                    color: alpha(red, 0.4 + 0.4 * _pulse.value),
                    blurRadius: 6 + 6 * _pulse.value,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'LIVE · Mode lihat saja${widget.ownerName != null ? ' · oleh ${widget.ownerName}' : ''}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: alpha(Colors.white, 0.85),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
            child: const Text('Buat sendiri'),
          ),
        ],
      ),
    );
  }

  Widget _progress() {
    final total = t.totalMatches, done = t.doneMatches;
    final v = total == 0 ? 0.0 : done / total;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 6),
      child: Column(
        children: [
          Row(
            children: [
              Text('$done / $total pertandingan selesai',
                  style: TextStyle(color: alpha(Colors.white, 0.8), fontSize: 13)),
              const Spacer(),
              Text('${(v * 100).round()}%',
                  style: const TextStyle(
                      color: kTeal, fontWeight: FontWeight.w800, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.0, end: v),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (c, val, _) => ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: val,
                minHeight: 8,
                backgroundColor: alpha(Colors.white, 0.1),
                valueColor: const AlwaysStoppedAnimation<Color>(kTeal),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _roundHeader(int r) {
    final rd = t.rounds[r];
    final done = rd.matches.every((m) => m.played);
    final isFinal = r == t.rounds.length - 1;
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: isFinal
              ? const LinearGradient(colors: [kGold, Color(0xFFFF9F43)])
              : null,
          color: isFinal ? null : alpha(Colors.white, 0.1),
          border: Border.all(color: alpha(Colors.white, 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              roundName(r, t.rounds.length, rd.matches.length),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: isFinal ? kBg1 : Colors.white,
              ),
            ),
            if (done)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(Icons.check_circle,
                    size: 16, color: isFinal ? kBg1 : kTeal),
              ),
          ],
        ),
      ),
    );
  }

  Widget _byeCard(int? id) {
    return Container(
      decoration: BoxDecoration(
        color: alpha(Colors.white, 0.04),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: alpha(Colors.white, 0.15)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(Icons.fast_forward_rounded, size: 18, color: alpha(kGold, 0.9)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'BYE · ${id == null ? 'menunggu' : t.names[id]}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: alpha(Colors.white, 0.8),
                fontStyle: FontStyle.italic,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _trophyNode() {
    final champ = t.champion;
    return _Pressable(
      onTap: champ != null ? _celebrate : null,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          final g = champ != null ? _pulse.value : 0.0;
          return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: champ != null
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [kGold, Color(0xFFFF9F43)],
                        )
                      : null,
                  color: champ != null ? null : alpha(Colors.white, 0.08),
                  border: Border.all(
                    color: champ != null ? kGold : alpha(Colors.white, 0.18),
                    width: 2,
                  ),
                  boxShadow: champ != null
                      ? [BoxShadow(color: alpha(kGold, 0.25 + 0.35 * g), blurRadius: 14 + 18 * g)]
                      : const <BoxShadow>[],
                ),
                child: Icon(Icons.emoji_events_rounded,
                    size: 38, color: champ != null ? kBg1 : alpha(Colors.white, 0.35)),
              ),
              const SizedBox(height: 8),
              Text(
                champ != null ? t.names[champ] : 'Juara',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: champ != null ? kGold : alpha(Colors.white, 0.4),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _canvas(_Geo g) {
    final R = t.rounds.length;
    final children = <Widget>[
      Positioned.fill(child: CustomPaint(painter: _LinkPainter(g.links))),
    ];

    for (var r = 0; r < R; r++) {
      final name = roundName(r, R, t.rounds[r].matches.length);
      children.add(Positioned(
        left: _x(r),
        top: 8,
        width: cardW,
        child: _roundHeader(r),
      ));
      for (var i = 0; i < t.rounds[r].matches.length; i++) {
        final m = t.rounds[r].matches[i];
        children.add(Positioned(
          left: _x(r),
          top: _y(g.matchY[r][i]) - cardH / 2,
          width: cardW,
          height: cardH,
          child: _MatchCard(
            m: m,
            names: t.names,
            pulse: _pulse,
            onTap: () => _edit(m, name),
            readOnly: widget.readOnly,
          ),
        ));
      }
      if (t.rounds[r].hasBye) {
        children.add(Positioned(
          left: _x(r),
          top: _y(g.byeY[r]!) - 22,
          width: cardW,
          height: 44,
          child: _byeCard(t.rounds[r].bye),
        ));
      }
    }

    // piala
    children.add(Positioned(
      left: _x(R),
      top: _y(g.finalY) - 62,
      width: trophyW,
      height: 124,
      child: _trophyNode(),
    ));

    // juara 3
    if (t.hasThird) {
      final cy = _y(g.finalY + slot * 1.3);
      children.add(Positioned(
        left: _x(R - 1),
        top: cy - cardH / 2 - 30,
        width: cardW,
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: alpha(const Color(0xFFCD7F32), 0.25),
              border: Border.all(color: alpha(const Color(0xFFCD7F32), 0.7)),
            ),
            child: const Text('Perebutan Juara 3',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ),
        ),
      ));
      children.add(Positioned(
        left: _x(R - 1),
        top: cy - cardH / 2,
        width: cardW,
        height: cardH,
        child: _MatchCard(
          m: t.third,
          names: t.names,
          pulse: _pulse,
          onTap: () => _edit(t.third, 'Perebutan Juara 3'),
          readOnly: widget.readOnly,
        ),
      ));
    }

    return SizedBox(
      width: g.width,
      height: g.height,
      child: Stack(clipBehavior: Clip.none, children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kBg1,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const BracketLogo(size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                  Text('BO${t.bestOf} · ${t.names.length} peserta',
                      style: TextStyle(
                          fontSize: 12, color: alpha(Colors.white, 0.6))),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.readOnly && !Navigator.of(context).canPop())
            IconButton(
              tooltip: 'Bracket Saya',
              icon: const Icon(Icons.grid_view_rounded),
              onPressed: () =>
                  Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
            ),
          IconButton(
            tooltip: 'Salin link share',
            icon: const Icon(Icons.share_rounded),
            onPressed: _copyLink,
          ),
          IconButton(
            tooltip: 'Pas-kan tampilan',
            icon: const Icon(Icons.fit_screen_rounded),
            onPressed: _fit,
          ),
          if (!widget.readOnly)
          IconButton(
            tooltip: 'Reset semua hasil',
            icon: const Icon(Icons.restart_alt_rounded),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset semua hasil?'),
                  content: const Text('Semua skor akan dihapus, peserta tetap sama.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reset')),
                  ],
                ),
              );
              if (ok == true && mounted) {
                setState(() {
                  t.resetAll();
                  _celebrated = null;
                });
                _save();
              }
            },
          ),
        ],
      ),
      floatingActionButton: t.champion != null
          ? FloatingActionButton.extended(
              onPressed: _celebrate,
              backgroundColor: kGold,
              foregroundColor: kBg1,
              icon: const Icon(Icons.emoji_events_rounded),
              label: const Text('Lihat Juara',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: GradientBg(
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _progress(),
              if (widget.readOnly) _viewerBanner(),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                child: Row(
                  children: [
                    Icon(Icons.touch_app_rounded,
                        size: 14, color: alpha(Colors.white, 0.5)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        widget.readOnly
                            ? 'Skor diperbarui otomatis · cubit untuk zoom'
                            : 'Ketuk kartu yang bersinar untuk isi skor · cubit untuk zoom',
                        style: TextStyle(color: alpha(Colors.white, 0.5), fontSize: 11),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, cons) {
                    final g = _geo();
                    _vp = Size(cons.maxWidth, cons.maxHeight);
                    _content = Size(g.width, g.height);
                    if (!_fitted) {
                      _fitted = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) _fit();
                      });
                    }
                    return ClipRect(
                      child: InteractiveViewer(
                        transformationController: _tc,
                        constrained: false,
                        minScale: 0.25,
                        maxScale: 3,
                        boundaryMargin: const EdgeInsets.all(160),
                        child: _canvas(g),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BOTTOM SHEET INPUT SKOR
// ============================================================

class _ScoreSheet extends StatefulWidget {
  final Tournament t;
  final MatchModel m;
  final String title;
  const _ScoreSheet({required this.t, required this.m, required this.title});

  @override
  State<_ScoreSheet> createState() => _ScoreSheetState();
}

class _ScoreSheetState extends State<_ScoreSheet> {
  late int sa = widget.m.sa;
  late int sb = widget.m.sb;
  late int? pick = (widget.m.played && widget.m.sa == widget.m.sb)
      ? (widget.m.winner == widget.m.a ? 0 : 1)
      : null;

  Tournament get t => widget.t;
  int get bo => t.bestOf;

  String get _hint {
    switch (bo) {
      case 1:
        return 'BO1 · pemenang ditentukan 1 game';
      case 2:
        return 'BO2 · skor 2-0, atau seri 1-1 lalu pilih pemenang (tie-break)';
      default:
        return 'BO3 · siapa yang lebih dulu menang 2 game';
    }
  }

  Widget _side({
    required int id,
    required int score,
    required bool win,
    required VoidCallback? onInc,
    required VoidCallback? onDec,
  }) {
    final name = t.names[id];
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          color: win ? alpha(kTeal, 0.12) : alpha(Colors.white, 0.05),
          border: Border.all(
            color: win ? kTeal : alpha(Colors.white, 0.1),
            width: win ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: teamColor(id),
              child: Text(initialOf(name),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 40,
              child: Center(
                child: Text(name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
              child: Text(
                '$score',
                key: ValueKey(score),
                style: TextStyle(
                    fontSize: 52,
                    fontWeight: FontWeight.w800,
                    color: win ? kTeal : Colors.white),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _RoundBtn(icon: Icons.remove, onTap: onDec, size: 40),
                const SizedBox(width: 12),
                _RoundBtn(icon: Icons.add, onTap: onInc, size: 40),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.m;
    final idA = m.a!, idB = m.b!;
    final d = BoRule.decide(bo, sa, sb);
    final winSide = d == null ? null : (d == -1 ? pick : d);
    final ok = winSide != null;

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF2A1B6B), kBg1],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: alpha(Colors.white, 0.15))),
      ),
      padding: EdgeInsets.fromLTRB(
          20, 12, 20, 20 + MediaQuery.of(context).viewPadding.bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: alpha(Colors.white, 0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 14),
            Text(widget.title,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
            const SizedBox(height: 4),
            Text(_hint,
                textAlign: TextAlign.center,
                style: TextStyle(color: alpha(Colors.white, 0.6), fontSize: 12)),
            const SizedBox(height: 16),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _side(
                  id: idA,
                  score: sa,
                  win: winSide == 0,
                  onInc: (sa + sb < bo && sa < 2) ? () => setState(() => sa++) : null,
                  onDec: sa > 0 ? () => setState(() => sa--) : null,
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 70),
                  child: Text('VS',
                      style: TextStyle(
                          color: alpha(Colors.white, 0.4),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1)),
                ),
                _side(
                  id: idB,
                  score: sb,
                  win: winSide == 1,
                  onInc: (sa + sb < bo && sb < 2) ? () => setState(() => sb++) : null,
                  onDec: sb > 0 ? () => setState(() => sb--) : null,
                ),
              ],
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              child: d == -1
                  ? Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: Column(
                        children: [
                          Text('Seri! Pilih pemenang (tie-break):',
                              style: TextStyle(color: alpha(Colors.white, 0.8))),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ChoiceChip(
                                label: Text(t.names[idA]),
                                selected: pick == 0,
                                onSelected: (_) => setState(() => pick = 0),
                              ),
                              ChoiceChip(
                                label: Text(t.names[idB]),
                                selected: pick == 1,
                                onSelected: (_) => setState(() => pick = 1),
                              ),
                            ],
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: ok
                  ? Row(
                      key: const ValueKey('ok'),
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.emoji_events_rounded, color: kGold, size: 20),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            '${t.names[winSide == 0 ? idA : idB]} menang! Tekan Selesaikan.',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: kGold, fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                      ],
                    )
                  : Text('Syarat BO belum terpenuhi. Simpan sementara dulu, selesaikan nanti.',
                      key: const ValueKey('no'),
                      style: TextStyle(color: alpha(Colors.white, 0.45))),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: _GradientButton(
                label: 'Selesaikan match',
                icon: Icons.check_rounded,
                colors: const [kTeal, Color(0xFF12B7A0)],
                onTap: ok
                    ? () => Navigator.pop(
                        context, _Res(sa, sb, winSide!, finish: true))
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18)),
                  side: BorderSide(color: alpha(Colors.white, 0.25)),
                ),
                onPressed: () => Navigator.pop(context, _Res(sa, sb, -1)),
                icon: const Icon(Icons.save_outlined, size: 20),
                label: const Text('Simpan sementara'),
              ),
            ),
            if (m.played || m.sa > 0 || m.sb > 0)
              TextButton(
                onPressed: () =>
                    Navigator.pop(context, const _Res(0, 0, 0, clear: true)),
                child: const Text('Reset skor match ini'),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// PERAYAAN JUARA (confetti + podium)
// ============================================================

class _Confetto {
  final double x, size, phase, rot;
  final int speed;
  final Color color;
  const _Confetto(this.x, this.size, this.phase, this.rot, this.speed, this.color);
}

class _ConfettiPainter extends CustomPainter {
  final List<_Confetto> items;
  final Animation<double> anim;
  _ConfettiPainter(this.items, this.anim) : super(repaint: anim);

  @override
  void paint(Canvas canvas, Size s) {
    final t = anim.value;
    final paint = Paint();
    for (final p in items) {
      final prog = (t * p.speed + p.phase) % 1.0;
      final y = prog * (s.height + 80) - 40;
      final x = p.x * s.width + sin(prog * 10 + p.phase * 6) * 24;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(prog * 12 * p.rot);
      paint.color = p.color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.5),
          const Radius.circular(2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter old) => false;
}

class _Celebration extends StatefulWidget {
  final Tournament t;
  const _Celebration({required this.t});

  @override
  State<_Celebration> createState() => _CelebrationState();
}

class _CelebrationState extends State<_Celebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final List<_Confetto> _items;

  @override
  void initState() {
    super.initState();
    final rnd = Random();
    const colors = [kGold, kTeal, kAccent, Color(0xFFFF6B9D), Colors.white, Color(0xFF5B8CFF)];
    _items = List.generate(
      80,
      (_) => _Confetto(
        rnd.nextDouble(),
        8 + rnd.nextDouble() * 10,
        rnd.nextDouble(),
        0.4 + rnd.nextDouble(),
        rnd.nextBool() ? 1 : 2,
        colors[rnd.nextInt(colors.length)],
      ),
    );
    _c = AnimationController(vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _row(int delayMs, Color medal, String label, String? name) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 500 + delayMs),
      curve: Curves.easeOutCubic,
      builder: (c, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0).toDouble(),
        child: Transform.translate(offset: Offset((1 - v) * 40, 0), child: child),
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: alpha(Colors.white, 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: alpha(medal, 0.6)),
        ),
        child: Row(
          children: [
            Icon(Icons.workspace_premium_rounded, color: medal, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(color: alpha(Colors.white, 0.6), fontSize: 12)),
                  Text(
                    name ?? 'Menunggu perebutan juara 3',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final champ = t.champion;
    final second = t.runnerUp;
    final third = t.thirdWinner;
    final w = min(380.0, MediaQuery.of(context).size.width - 40);

    return Stack(
      children: [
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ConfettiPainter(_items, _c)),
          ),
        ),
        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: w,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF2E1D78), Color(0xFF14102F)],
                ),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: alpha(kGold, 0.6), width: 1.5),
                boxShadow: [BoxShadow(color: alpha(kGold, 0.25), blurRadius: 40)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedBuilder(
                    animation: _c,
                    builder: (_, __) => Transform.scale(
                      scale: 1 + 0.06 * sin(_c.value * 2 * pi * 6),
                      child: const Icon(Icons.emoji_events_rounded, size: 76, color: kGold),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('SELAMAT!',
                      style: TextStyle(
                          color: kGold,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 4,
                          fontSize: 14)),
                  const SizedBox(height: 6),
                  Text(
                    champ == null ? '-' : t.names[champ],
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w900, fontSize: 30),
                  ),
                  Text('Juara 1',
                      style: TextStyle(color: alpha(Colors.white, 0.6))),
                  const SizedBox(height: 6),
                  if (second != null)
                    _row(100, const Color(0xFFC0C8D6), 'Juara 2', t.names[second]),
                  if (t.hasThird)
                    _row(250, const Color(0xFFCD7F32), 'Juara 3',
                        third == null ? null : t.names[third]),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: _GradientButton(
                      label: 'Tutup',
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================
// ROUTING (link share: https://.../#/b/ID_BRACKET)
// ============================================================

Route<dynamic> appRoute(RouteSettings s) {
  try {
    final seg = Uri.parse(s.name ?? '/').pathSegments;
    if (seg.length == 2 && seg[0] == 'b' && seg[1].isNotEmpty) {
      return fadeSlide(CloudBracketPage(id: seg[1]), name: '/b/${seg[1]}');
    }
  } catch (_) {}
  return fadeSlide(const AuthGate(), name: '/');
}

String shareUrlFor(String id) {
  var base = kIsWeb ? Uri.base.removeFragment().toString() : kShareBase;
  if (!base.endsWith('/')) base += '/';
  return '$base#/b/$id';
}

String? parseBracketId(String input) {
  final s = input.trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'/b/([A-Za-z0-9]+)').firstMatch(s);
  if (m != null) return m.group(1);
  if (RegExp(r'^[A-Za-z0-9]{10,}$').hasMatch(s)) return s;
  return null;
}

String _fmtDate(DateTime d) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];
  return '${d.day} ${m[d.month - 1]} ${d.year}';
}

Future<void> openByLinkDialog(BuildContext context) async {
  final ctrl = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Buka bracket dari link'),
      content: TextField(
        controller: ctrl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Tempel link atau ID bracket'),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('Buka'),
        ),
      ],
    ),
  );
  if (text == null || text.trim().isEmpty || !context.mounted) return;
  final id = parseBracketId(text);
  if (id == null) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text('Link tidak valid.'),
    ));
    return;
  }
  Navigator.push(context, fadeSlide(CloudBracketPage(id: id), name: '/b/$id'));
}

// ============================================================
// FIREBASE: AUTH + FIRESTORE
// ============================================================

class Auth {
  static Future<void> signInGoogle() async {
    final provider = GoogleAuthProvider();
    if (kIsWeb) {
      await FirebaseAuth.instance.signInWithPopup(provider);
    } else {
      await FirebaseAuth.instance.signInWithProvider(provider);
    }
  }

  static Future<void> signOut() => FirebaseAuth.instance.signOut();
}

class Repo {
  static CollectionReference<Map<String, dynamic>> get col =>
      FirebaseFirestore.instance.collection('brackets');

  static Future<String> create({
    required User user,
    required String title,
    required Tournament t,
  }) async {
    final ref = col.doc();
    await ref.set({
      'ownerId': user.uid,
      'ownerName': user.displayName ?? 'Pembuat',
      'title': title,
      'names': t.names,
      'order': t.order,
      'bestOf': t.bestOf,
      'thirdPlace': t.thirdPlace,
      'results': <String, dynamic>{},
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    }).timeout(const Duration(seconds: 20));
    return ref.id;
  }

  static Future<void> saveResults(String id, Tournament t) => col.doc(id).update({
        'results': t.resultsMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

  static Future<void> delete(String id) => col.doc(id).delete();

  static Stream<DocumentSnapshot<Map<String, dynamic>>> watch(String id) =>
      col.doc(id).snapshots();

  static Stream<QuerySnapshot<Map<String, dynamic>>> mine(String uid) =>
      col.where('ownerId', isEqualTo: uid).snapshots();
}

// ============================================================
// AUTH GATE + LOGIN
// ============================================================

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: GradientBg(
              child: Center(child: CircularProgressIndicator(color: kTeal)),
            ),
          );
        }
        final user = snap.data;
        return user == null ? const LoginPage() : MyBracketsPage(user: user);
      },
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  bool _busy = false;

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(msg),
    ));
  }

  Future<void> _login() async {
    setState(() => _busy = true);
    try {
      await Auth.signInGoogle();
    } on FirebaseAuthException catch (e) {
      const ignore = {
        'popup-closed-by-user',
        'cancelled-popup-request',
        'web-context-canceled',
        'canceled',
      };
      if (!ignore.contains(e.code) && mounted) {
        _snack('Login gagal: ${e.message ?? e.code}');
      }
    } catch (e) {
      if (mounted) _snack('Login gagal: $e');
    }
    if (mounted) setState(() => _busy = false);
  }

  Widget _feature(IconData icon, String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: kTeal, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(text,
                  style: TextStyle(color: alpha(Colors.white, 0.85), fontSize: 14)),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const BracketLogo(size: 110),
                    const SizedBox(height: 20),
                    const Text('Bracket Arena',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5)),
                    const SizedBox(height: 8),
                    Text(
                      'Buat bagan turnamen, simpan, dan bagikan progresnya lewat link.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: alpha(Colors.white, 0.7)),
                    ),
                    const SizedBox(height: 28),
                    Glass(
                      child: Column(
                        children: [
                          _feature(Icons.cloud_done_rounded,
                              'Semua bracketmu tersimpan di akun'),
                          _feature(Icons.link_rounded,
                              'Bagikan link, teman lihat skor secara live'),
                          _feature(Icons.lock_rounded,
                              'Hanya kamu yang bisa edit atau hapus skor'),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: _GradientButton(
                        label: _busy ? 'Menghubungkan...' : 'Masuk dengan Google',
                        icon: Icons.login_rounded,
                        onTap: _busy ? null : _login,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () => openByLinkDialog(context),
                      icon: const Icon(Icons.link_rounded, size: 18),
                      label: const Text('Punya link bracket? Buka di sini'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// BRACKET SAYA
// ============================================================

class MyBracketsPage extends StatelessWidget {
  final User user;
  const MyBracketsPage({super.key, required this.user});

  void _snack(BuildContext c, String m) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(
      behavior: SnackBarBehavior.floating,
      content: Text(m),
    ));
  }

  Future<void> _copy(BuildContext context, String id) async {
    await Clipboard.setData(ClipboardData(text: shareUrlFor(id)));
    if (context.mounted) _snack(context, 'Link disalin. Kirim ke temanmu!');
  }

  Future<void> _delete(BuildContext context, String id, String title) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus bracket?'),
        content: Text('"$title" akan dihapus permanen dan link share-nya tidak bisa dibuka lagi.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Batal')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await Repo.delete(id);
    } catch (e) {
      if (context.mounted) _snack(context, 'Gagal menghapus: $e');
    }
  }

  Widget _header(BuildContext context) {
    final first = (user.displayName ?? 'Kawan').split(' ').first;
    final photo = user.photoURL;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          const BracketLogo(size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bracket Saya',
                    style: TextStyle(
                        color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                Text('Halo, $first',
                    style: TextStyle(color: alpha(Colors.white, 0.65))),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Akun',
            onSelected: (v) async {
              if (v == 'link') {
                await openByLinkDialog(context);
              } else if (v == 'out') {
                await Auth.signOut();
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'link', child: Text('Buka dari link')),
              PopupMenuItem(value: 'out', child: Text('Keluar')),
            ],
            child: CircleAvatar(
              radius: 21,
              backgroundColor: kAccent,
              foregroundImage: photo != null ? NetworkImage(photo) : null,
              onForegroundImageError: photo != null ? (_, __) {} : null,
              child: Text(initialOf(user.displayName ?? user.email ?? '?'),
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    Tournament t;
    try {
      t = Tournament.fromData(d);
    } catch (_) {
      return const SizedBox.shrink();
    }
    final title = (d['title'] as String?) ?? 'Tanpa judul';
    final champ = t.champion;
    final done = t.doneMatches, total = t.totalMatches;
    final created = (d['createdAt'] as Timestamp?)?.toDate();
    final finished = champ != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: _Pressable(
        onTap: () => Navigator.push(
          context,
          fadeSlide(CloudBracketPage(id: doc.id), name: '/b/${doc.id}'),
        ),
        child: Glass(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: alpha(finished ? kGold : kTeal, 0.18),
                    ),
                    child: Icon(
                      finished ? Icons.emoji_events_rounded : Icons.account_tree_rounded,
                      color: finished ? kGold : kTeal,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        Text(
                          'BO${t.bestOf} · ${t.names.length} peserta${created != null ? ' · ${_fmtDate(created)}' : ''}',
                          style: TextStyle(color: alpha(Colors.white, 0.6), fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Salin link share',
                    icon: const Icon(Icons.share_rounded, size: 20),
                    onPressed: () => _copy(context, doc.id),
                  ),
                  IconButton(
                    tooltip: 'Hapus',
                    icon: const Icon(Icons.delete_outline_rounded, size: 22),
                    onPressed: () => _delete(context, doc.id, title),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: total == 0 ? 0.0 : done / total,
                    minHeight: 6,
                    backgroundColor: alpha(Colors.white, 0.1),
                    valueColor: AlwaysStoppedAnimation<Color>(finished ? kGold : kTeal),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                finished ? 'Juara: ${t.names[champ]}' : '$done / $total pertandingan selesai',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: finished ? kGold : alpha(Colors.white, 0.7),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, fadeSlide(const SetupPage())),
        backgroundColor: kAccent,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Bracket Baru', style: TextStyle(fontWeight: FontWeight.w800)),
      ),
      body: GradientBg(
        child: SafeArea(
          child: Column(
            children: [
              _header(context),
              Expanded(
                child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: Repo.mine(user.uid),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Gagal memuat bracket.\n${snap.error}',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: alpha(Colors.white, 0.7)),
                          ),
                        ),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator(color: kTeal));
                    }
                    final docs = snap.data!.docs.toList();
                    int ts(QueryDocumentSnapshot<Map<String, dynamic>> d) =>
                        (d.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ??
                        DateTime.now().millisecondsSinceEpoch;
                    docs.sort((a, b) => ts(b).compareTo(ts(a)));

                    if (docs.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.account_tree_rounded,
                                  size: 72, color: alpha(Colors.white, 0.3)),
                              const SizedBox(height: 16),
                              const Text('Belum ada bracket',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              Text('Ketuk "Bracket Baru" untuk membuat turnamen pertamamu.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: alpha(Colors.white, 0.6))),
                            ],
                          ),
                        ),
                      );
                    }
                    return Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 640),
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                          children: [for (final d in docs) _tile(context, d)],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// HALAMAN BRACKET DARI FIRESTORE (pemilik = bisa edit, lainnya = lihat saja)
// ============================================================

class CloudBracketPage extends StatelessWidget {
  final String id;
  const CloudBracketPage({super.key, required this.id});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        final uid = authSnap.data?.uid;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: Repo.watch(id),
          builder: (context, snap) {
            if (snap.hasError) {
              return _MessagePage(
                icon: Icons.error_outline_rounded,
                title: 'Tidak bisa membuka bracket',
                text: '${snap.error}',
              );
            }
            if (!snap.hasData) {
              return const Scaffold(
                body: GradientBg(
                  child: Center(child: CircularProgressIndicator(color: kTeal)),
                ),
              );
            }
            final doc = snap.data!;
            if (!doc.exists) {
              return const _MessagePage(
                icon: Icons.search_off_rounded,
                title: 'Bracket tidak ditemukan',
                text: 'Link salah atau bracket sudah dihapus oleh pembuatnya.',
              );
            }
            final data = doc.data()!;
            final Tournament t;
            try {
              t = Tournament.fromData(data);
            } catch (_) {
              return const _MessagePage(
                icon: Icons.broken_image_outlined,
                title: 'Data bracket rusak',
                text: 'Bracket ini tidak bisa dibaca.',
              );
            }
            final isOwner = uid != null && uid == data['ownerId'];
            return BracketPage(
              key: ValueKey('bracket-$id'),
              t: t,
              title: (data['title'] as String?) ?? 'Bracket',
              ownerName: data['ownerName'] as String?,
              shareUrl: shareUrlFor(id),
              readOnly: !isOwner,
              onSave: isOwner ? (tt) => Repo.saveResults(id, tt) : null,
            );
          },
        );
      },
    );
  }
}

class _MessagePage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  const _MessagePage({required this.icon, required this.title, required this.text});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 64, color: alpha(Colors.white, 0.5)),
                  const SizedBox(height: 16),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Text(text,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: alpha(Colors.white, 0.65))),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: 240,
                    child: _GradientButton(
                      label: 'Ke Beranda',
                      icon: Icons.home_rounded,
                      onTap: () =>
                          Navigator.pushNamedAndRemoveUntil(context, '/', (r) => false),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}