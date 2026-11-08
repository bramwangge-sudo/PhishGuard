import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
 
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
 
import '../constants/app_colors.dart';
import '../models/detection_result.dart';
 
// ============================================================
// PALET WARNA (merah dibuat lebih lembut: rose/coral)
// ============================================================
const Color kDanger = Color(0xFFFB7185); // rose-400, merah utama
const Color kDangerDeep = Color(0xFFE11D48); // rose-600, ujung gradient
const Color kDangerBg = Color(0xFF3B1220); // latar gelap kemerahan
const Color kSafe = Color(0xFF34D399);
const Color kSafeDeep = Color(0xFF059669);
 
const String _apiBaseOverride = String.fromEnvironment('API_BASE');
 
String get apiBaseUrl {
  if (_apiBaseOverride.isNotEmpty) return _apiBaseOverride;
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    return 'http://10.0.2.2:8000';
  }
  return 'http://127.0.0.1:8000';
}
 
class DetectionPage extends StatefulWidget {
  const DetectionPage({super.key});
 
  @override
  State<DetectionPage> createState() => _DetectionPageState();
}
 
class _DetectionPageState extends State<DetectionPage> {
  final TextEditingController _urlController = TextEditingController();
 
  bool _isLoading = false;
  String _error = '';
  DetectionResult? _result;
  int? _responseTimeMs;
  bool _isDarkMode = true;
 
  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }
 
  /// Validasi struktur URL sebelum dikirim ke backend.
  /// Tidak memeriksa apakah domain benar-benar terdaftar atau aktif.
  bool _looksLikeUrl(String input) {
    final value = input.trim();
    if (value.isEmpty || value.length > 2048) return false;
    if (RegExp(r'\s').hasMatch(value)) return false;
    if (RegExp(r'[<>\"{}|\\^`]').hasMatch(value)) return false;

    // Hanya karakter yang lazim ditemukan pada URL.
    if (!RegExp(r"^[A-Za-z0-9._~:/?#\[\]@!$&'()*+,;=%-]+$").hasMatch(value)) return false;
    if (RegExp(r'%(?![0-9A-Fa-f]{2})').hasMatch(value)) return false;

    final candidate = value.contains('://') ? value : 'https://$value';
    final uri = Uri.tryParse(candidate);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) return false;
    if (uri.scheme != 'http' && uri.scheme != 'https') return false;
    if (uri.userInfo.isNotEmpty) return false;

    final host = uri.host.toLowerCase();
    if (host == 'localhost') return false;
    final isIpv4 = RegExp(r'^(?:\d{1,3}\.){3}\d{1,3}$').hasMatch(host);
    if (isIpv4) {
      final parts = host.split('.');
      if (parts.any((part) => int.tryParse(part) == null || int.parse(part) > 255)) return false;
    } else {
      if (!host.contains('.') || host.length > 253) return false;
      final labels = host.split('.');
      if (labels.any((label) => label.isEmpty || label.length > 63 ||
          !RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(label))) return false;
      if (labels.last.length < 2 || !RegExp(r'^[a-z0-9-]+$').hasMatch(labels.last)) return false;
    }

    try {
      final port = uri.port;
      if (port < 1 || port > 65535) return false;
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<void> _analyze() async {
    final input = _urlController.text.trim();
 
    if (input.isEmpty) {
      setState(() => _error = 'Masukkan URL terlebih dahulu.');
      return;
    }
 
    if (!_looksLikeUrl(input)) {
      setState(() {
        _error = 'Input tidak terdeteksi sebagai URL. '
            'Pastikan ada nama domain, contoh: contoh.com/login';
        _result = null; // hapus hasil lama agar tidak menyesatkan
        _responseTimeMs = null;
      });
      return;
    }
 
    setState(() {
      _isLoading = true;
      _error = '';
    });
 
    final stopwatch = Stopwatch()..start();
 
    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/predict'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'url': input}),
          )
          .timeout(const Duration(seconds: 15));
 
      stopwatch.stop();
 
      if (!mounted) return;
 
      if (response.statusCode == 200) {
        final data =
            jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
 
        setState(() {
          _result = DetectionResult.fromJson(data);
          _responseTimeMs = stopwatch.elapsedMilliseconds;
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response.statusCode == 422
              ? 'Format URL tidak valid.'
              : 'Server mengembalikan kesalahan (${response.statusCode}).';
          _isLoading = false;
        });
      }
    } on TimeoutException {
      if (!mounted) return;
 
      setState(() {
        _error = 'Server tidak merespons. Coba lagi sebentar.';
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
 
      setState(() {
        _error =
            'Tidak dapat terhubung ke server ($apiBaseUrl). Pastikan backend FastAPI aktif.';
        _isLoading = false;
      });
    }
  }
 
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isSplit = width >= 980;
    final dark = _isDarkMode;
    final r = _result;
 
    final bgScaffold = dark ? const Color(0xFF0B0F19) : const Color(0xFFF3F4F6);
    final bgAppBar = dark ? const Color(0xFF111827) : Colors.white;
    final textMain = dark ? Colors.white : const Color(0xFF1F2937);
    final textSub = dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
 
    // ---------------- Panel-panel ----------------
    final inputPanel = _Panel(
      icon: Icons.link_rounded,
      title: 'INPUT URL',
      isDarkMode: dark,
      child: _buildInputBody(dark),
    );
 
    final resultPanel = _Panel(
      icon: Icons.fact_check_outlined,
      title: 'HASIL ANALISIS',
      isDarkMode: dark,
      fill: isSplit,
      child: r == null
          ? _EmptyHint(
              icon: Icons.shield_outlined,
              title: 'Belum ada hasil',
              text: 'Masukkan URL lalu tekan "Analisis URL".',
              isDarkMode: dark,
            )
          : _ResultBody(
              result: r,
              responseTimeMs: _responseTimeMs,
              isDarkMode: dark,
            ),
    );
 
    final featurePanel = _Panel(
      icon: Icons.tune_rounded,
      title: r == null ? 'DETAIL FITUR' : 'DETAIL FITUR (${r.featureCount})',
      isDarkMode: dark,
      fill: isSplit,
      child: r == null
          ? _EmptyHint(
              icon: Icons.account_tree_outlined,
              title: 'Fitur belum tersedia',
              text: 'Fitur leksikal URL akan tampil setelah analisis.',
              isDarkMode: dark,
            )
          : _FeatureGrid(result: r, isDarkMode: dark),
    );
 
    final forestPanel = _Panel(
      icon: Icons.account_tree_outlined,
      title: 'RANDOM FOREST',
      isDarkMode: dark,
      child: r == null
          ? Text(
              'Detail voting pohon keputusan tampil setelah analisis.',
              style: TextStyle(fontSize: 13, color: textSub),
            )
          : _ForestBody(result: r, isDarkMode: dark),
    );
 
    final errorBanner = _error.isEmpty ? null : _buildErrorBanner(_error);
 
    Widget body;
    if (isSplit) {
      body = Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // KIRI: input + hasil prediksi
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  inputPanel,
                  if (errorBanner != null) ...[
                    const SizedBox(height: 12),
                    errorBanner,
                  ],
                  const SizedBox(height: 12),
                  Expanded(child: resultPanel),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // KANAN: fitur + random forest
            Expanded(
              flex: 6,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: featurePanel),
                  const SizedBox(height: 12),
                  forestPanel,
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      body = SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: width < 600 ? 12 : 20,
          vertical: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            inputPanel,
            if (errorBanner != null) ...[
              const SizedBox(height: 12),
              errorBanner,
            ],
            const SizedBox(height: 12),
            resultPanel,
            const SizedBox(height: 12),
            featurePanel,
            const SizedBox(height: 12),
            forestPanel,
            const SizedBox(height: 12),
            Text(
              'Hasil bersifat estimasi berdasarkan model Random Forest.',
              style: TextStyle(fontSize: 12, color: textSub),
            ),
          ],
        ),
      );
    }
 
    return Scaffold(
      backgroundColor: bgScaffold,
      appBar: AppBar(
        toolbarHeight: 68,
        backgroundColor: bgAppBar,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: dark
                ? Colors.white.withOpacity(0.1)
                : Colors.black.withOpacity(0.1),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xFF2563EB),
                borderRadius: BorderRadius.circular(12),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x552563EB),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.shield_moon_outlined,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Deteksi URL Phishing',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: textMain,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Deteksi Dengan Model Ai Random Forest & Fitur Leksikal',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: textSub, height: 1.2),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                color: dark ? const Color(0xFFFBBF24) : const Color(0xFF4B5563),
                size: 20,
              ),
              onPressed: () => setState(() => _isDarkMode = !_isDarkMode),
              tooltip: dark ? 'Ganti ke Mode Terang' : 'Ganti ke Mode Gelap',
            ),
            const SizedBox(width: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: textMain,
                side: BorderSide(
                  color: dark
                      ? Colors.white.withOpacity(0.2)
                      : Colors.black.withOpacity(0.2),
                  width: 1.5,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              ),
              onPressed: () {
                if (kSamples.isNotEmpty) {
                  setState(() => _urlController.text = kSamples.first.url);
                }
              },
              child: Text(
                'Isi contoh URL',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textMain,
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(child: body),
    );
  }
 
  // ---------------- Isi panel INPUT URL ----------------
  Widget _buildInputBody(bool dark) {
    final fillColor = dark ? const Color(0xFF0B0F19) : Colors.white;
    final borderColor =
        dark ? const Color(0xFF374151) : const Color(0xFFD1D5DB);
    final textMain = dark ? Colors.white : const Color(0xFF1F2937);
    final textSub = dark ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
 
    final field = TextField(
      controller: _urlController,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.go,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: (_) => _analyze(),
      style: mono(14).copyWith(color: textMain),
      decoration: InputDecoration(
        isDense: true,
        prefixIcon: const Icon(
          Icons.link_rounded,
          size: 20,
          color: Color(0xFF60A5FA),
        ),
        hintStyle: TextStyle(fontSize: 14, color: textSub),
        filled: true,
        fillColor: fillColor,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        border: _outline(borderColor, 1),
        enabledBorder: _outline(borderColor, 1),
        focusedBorder: _outline(const Color(0xFF3B82F6), 2),
      ),
    );
 
    final button = SizedBox(
      height: 50,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2563EB),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF374151),
          disabledForegroundColor: const Color(0xFF9CA3AF),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
        onPressed: _isLoading ? null : _analyze,
        child: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.travel_explore_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Analisis'),
                ],
              ),
      ),
    );
 
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Masukkan alamat URL target',
          style: TextStyle(fontSize: 12, color: textSub),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth >= 340) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: field),
                  const SizedBox(width: 10),
                  button,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [field, const SizedBox(height: 10), button],
            );
          },
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Contoh URL:',
              style: TextStyle(fontSize: 12, color: textSub),
            ),
            for (final s in kSamples)
              SizedBox(
                height: 32,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: textMain,
                    side: BorderSide(color: borderColor, width: 1.2),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onPressed: () => setState(() => _urlController.text = s.url),
                  child: Text(s.label),
                ),
              ),
          ],
        ),
      ],
    );
  }
 
  OutlineInputBorder _outline(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: color, width: width),
    );
  }
 
  Widget _buildErrorBanner(String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDangerBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDanger.withOpacity(0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, size: 18, color: kDanger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: kDanger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
 
// ============================================================
// PANEL UMUM (header strip + isi)
// ============================================================
class _Panel extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;
  final bool isDarkMode;
 
  /// true -> panel mengisi sisa tinggi & isinya bisa di-scroll sendiri
  final bool fill;
 
  const _Panel({
    required this.icon,
    required this.title,
    required this.child,
    required this.isDarkMode,
    this.fill = false,
  });
 
  @override
  Widget build(BuildContext context) {
    final bg = isDarkMode ? const Color(0xFF111827) : Colors.white;
    final border =
        isDarkMode ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB);
    final headerBg =
        isDarkMode ? const Color(0xFF1B2540) : const Color(0xFFE8EEF9);
    final headerFg =
        isDarkMode ? const Color(0xFF93C5FD) : const Color(0xFF2563EB);
 
    final header = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      color: headerBg,
      child: Row(
        children: [
          Icon(icon, size: 16, color: headerFg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: headerFg,
              ),
            ),
          ),
        ],
      ),
    );
 
    final Widget body = fill
        ? Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          )
        : Padding(padding: const EdgeInsets.all(16), child: child);
 
    return Container(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color:
                isDarkMode ? const Color(0x33000000) : const Color(0x11000000),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(15),
        child: Column(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [header, body],
        ),
      ),
    );
  }
}
 
class _EmptyHint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final bool isDarkMode;
 
  const _EmptyHint({
    required this.icon,
    required this.title,
    required this.text,
    required this.isDarkMode,
  });
 
  @override
  Widget build(BuildContext context) {
    final textMain = isDarkMode ? Colors.white : const Color(0xFF1F2937);
    final textSub =
        isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
 
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Center(
        child: Column(
          children: [
            Icon(icon, size: 40, color: textSub.withOpacity(0.6)),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: textMain,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, height: 1.5, color: textSub),
            ),
          ],
        ),
      ),
    );
  }
}
 
// ============================================================
// ISI PANEL HASIL ANALISIS
// ============================================================
class _ResultBody extends StatelessWidget {
  final DetectionResult result;
  final int? responseTimeMs;
  final bool isDarkMode;
 
  const _ResultBody({
    required this.result,
    required this.responseTimeMs,
    required this.isDarkMode,
  });
 
  @override
  Widget build(BuildContext context) {
    final style = kVerdictStyles[result.level]!;
    final pPhish = result.probPhishing;
    final pctPhish = (pPhish * 100).round();
    final pctLegit = 100 - pctPhish;
    final isSafe = result.level == VerdictLevel.safe;
    final displayPercent = isSafe ? pctLegit : pctPhish;
    final accent = isSafe ? kSafe : kDanger;
 
    final textMain = isDarkMode ? Colors.white : const Color(0xFF1F2937);
    final textSub =
        isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final textBody =
        isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563);
    final boxBg =
        isDarkMode ? const Color(0xFF0B0F19) : const Color(0xFFF9FAFB);
    final boxBorder =
        isDarkMode ? const Color(0xFF374151) : const Color(0xFFD1D5DB);
    final textUrl =
        isDarkMode ? const Color(0xFFE5E7EB) : const Color(0xFF111827);
 
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _RiskScoreGauge(
              probability: isSafe ? (1.0 - pPhish) : pPhish,
              percent: displayPercent,
              color: style.fg,
              subLabel: isSafe ? 'SAFETY' : 'RISK SCORE',
              isSafe: isSafe,
              isDarkMode: isDarkMode,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: accent.withOpacity(0.14),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: accent.withOpacity(0.55),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      isSafe ? 'LEGITIMATE' : 'PHISHING',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: accent,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$displayPercent%',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: accent,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Skor model (probabilitas kelas prediksi)',
                    style: TextStyle(fontSize: 11, color: textSub),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'URL yang dianalisis',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textSub,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: boxBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: boxBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                result.url,
                style: mono(12).copyWith(color: textUrl),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF065F46),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Text(
                      'Ekstraksi fitur berhasil',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6EE7B7),
                      ),
                    ),
                  ),
                  Text(
                    responseTimeMs == null
                        ? 'Waktu respons: —'
                        : 'Respons: $responseTimeMs ms',
                    style: TextStyle(fontSize: 11, color: textSub),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          style.headline,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: textMain,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isSafe
              ? 'Model tidak menemukan indikasi phishing yang kuat berdasarkan karakteristik URL yang dianalisis.'
              : 'Model menemukan karakteristik URL yang mengindikasikan potensi aktivitas phishing.',
          style: TextStyle(fontSize: 13, height: 1.5, color: textBody),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ProbabilityLegend(
                label: 'Legitimate',
                percent: pctLegit,
                color: kSafe,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ProbabilityLegend(
                label: 'Phishing',
                percent: pctPhish,
                color: kDanger,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ProbabilityBar(pPhish: pPhish, isDarkMode: isDarkMode),
        const SizedBox(height: 8),
        Text(
          'Persentase adalah probabilitas menurut model Random Forest, bukan jaminan keamanan URL.',
          style: TextStyle(fontSize: 11, height: 1.4, color: textSub),
        ),
      ],
    );
  }
}
 
// ============================================================
// ISI PANEL DETAIL FITUR
// ============================================================
class _FeatureGrid extends StatelessWidget {
  final DetectionResult result;
  final bool isDarkMode;
 
  const _FeatureGrid({required this.result, required this.isDarkMode});
 
  @override
  Widget build(BuildContext context) {
    final textMain = isDarkMode ? Colors.white : const Color(0xFF1F2937);
    final gridBg =
        isDarkMode ? const Color(0xFF0B0F19) : const Color(0xFFF9FAFB);
    final gridBorder =
        isDarkMode ? const Color(0xFF374151) : const Color(0xFFD1D5DB);
 
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 220,
        mainAxisExtent: 52,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: result.features.length,
      itemBuilder: (context, index) {
        final item = result.features[index];
 
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: gridBg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: gridBorder),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textMain,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.value,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF60A5FA),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
 
// ============================================================
// ISI PANEL RANDOM FOREST
// ============================================================
class _ForestBody extends StatelessWidget {
  final DetectionResult result;
  final bool isDarkMode;
 
  const _ForestBody({required this.result, required this.isDarkMode});
 
  @override
  Widget build(BuildContext context) {
    final textSub =
        isDarkMode ? const Color(0xFF9CA3AF) : const Color(0xFF6B7280);
    final textBody =
        isDarkMode ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563);
 
    final isSafe = result.level == VerdictLevel.safe;
    final total = result.totalTrees;
    final phishVotes = result.treeVotes.clamp(0, total).toInt();
    final legitVotes = total - phishVotes;
 
    final phishFlex = phishVotes;
    final legitFlex = legitVotes;
 
    Widget stat(String label, String value, {Color? valueColor, String? tag}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: textSub),
                  ),
                ),
                if (tag != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: (valueColor ?? textBody).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: valueColor ?? textBody,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: valueColor ?? textBody,
              ),
            ),
          ],
        ),
      );
    }
 
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            stat('Total pohon', '$total'),
            stat(
              'Memilih legitimate',
              '$legitVotes',
              valueColor: kSafe,
              tag: isSafe ? 'PREDIKSI' : null,
            ),
            stat(
              'Memilih phishing',
              '$phishVotes',
              valueColor: kDanger,
              tag: isSafe ? null : 'PREDIKSI',
            ),
            stat('Fitur leksikal', '${result.featureCount}'),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Container(
            height: 8,
            color: isDarkMode
                ? const Color(0xFF374151)
                : const Color(0xFFE5E7EB),
            child: total == 0
                ? null
                : Row(
                    children: [
                      if (legitFlex > 0)
                        Expanded(
                          flex: legitFlex,
                          child: Container(color: kSafe),
                        ),
                      if (phishFlex > 0)
                        Expanded(
                          flex: phishFlex,
                          child: Container(
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                colors: [kDanger, kDangerDeep],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            Text(
              '$legitVotes dari $total pohon memilih legitimate',
              style: TextStyle(fontSize: 11, color: kSafe),
            ),
            Text(
              '$phishVotes dari $total pohon memilih phishing',
              style: TextStyle(fontSize: 11, color: kDanger),
            ),
          ],
        ),
      ],
    );
  }
}
 
// ============================================================
// WIDGET KECIL
// ============================================================
class _RiskScoreGauge extends StatelessWidget {
  final double probability;
  final int percent;
  final Color color;
  final String subLabel;
  final bool isSafe;
  final bool isDarkMode;
 
  const _RiskScoreGauge({
    required this.probability,
    required this.percent,
    required this.color,
    required this.subLabel,
    required this.isSafe,
    required this.isDarkMode,
  });
 
  @override
  Widget build(BuildContext context) {
    final value = probability.clamp(0.0, 1.0).toDouble();
    final ringColor = isSafe ? kSafe : kDanger;
 
    return SizedBox(
      width: 104,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDarkMode
                  ? const Color(0xFF1F2937)
                  : const Color(0xFFE5E7EB),
              border: Border.all(color: ringColor.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: ringColor.withOpacity(0.25),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 94,
            height: 94,
            child: CustomPaint(
              painter: _RiskRingPainter(
                progress: value,
                ringColor: ringColor,
                isDarkMode: isDarkMode,
              ),
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDarkMode ? const Color(0xFF111827) : Colors.white,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$percent%',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: ringColor,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'SCORE',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
 
class _RiskRingPainter extends CustomPainter {
  final double progress;
  final Color ringColor;
  final bool isDarkMode;
 
  _RiskRingPainter({
    required this.progress,
    required this.ringColor,
    required this.isDarkMode,
  });
 
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 4;
    final rect = Rect.fromCircle(center: center, radius: radius);
 
    const startAngle = -math.pi / 2;
    final sweepAngle = 2 * math.pi * progress;
 
    final bgPaint = Paint()
      ..color = isDarkMode ? const Color(0xFF374151) : const Color(0xFFD1D5DB)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6;
 
    canvas.drawCircle(center, radius, bgPaint);
 
    if (sweepAngle <= 0.01) return;
 
    final endColor = ringColor == kDanger ? kDangerDeep : kSafeDeep;
 
    // Glow lembut di belakang arc
    final glowPaint = Paint()
      ..color = ringColor.withOpacity(0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    canvas.drawArc(rect, startAngle, sweepAngle, false, glowPaint);
 
    // Arc utama dengan gradient
    final fgPaint = Paint()
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: sweepAngle,
        colors: [ringColor, endColor],
        transform: const GradientRotation(startAngle),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
 
    canvas.drawArc(rect, startAngle, sweepAngle, false, fgPaint);
  }
 
  @override
  bool shouldRepaint(covariant _RiskRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.ringColor != ringColor ||
        oldDelegate.isDarkMode != isDarkMode;
  }
}
 
class _ProbabilityLegend extends StatelessWidget {
  final String label;
  final int percent;
  final Color color;
 
  const _ProbabilityLegend({
    required this.label,
    required this.percent,
    required this.color,
  });
 
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label $percent%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}
 
class _ProbabilityBar extends StatelessWidget {
  final double pPhish;
  final bool isDarkMode;
 
  const _ProbabilityBar({required this.pPhish, required this.isDarkMode});
 
  @override
  Widget build(BuildContext context) {
    final safePhish = pPhish.clamp(0.0, 1.0).toDouble();
    final pctPhish = (safePhish * 100).round().clamp(0, 100);
    final pctLegit = 100 - pctPhish;
 
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 12,
        width: double.infinity,
        color: isDarkMode ? const Color(0xFF374151) : const Color(0xFFE5E7EB),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final legitWidth = constraints.maxWidth * (pctLegit / 100.0);
 
            return Row(
              children: [
                Container(
                  width: legitWidth,
                  height: 12,
                  color: kSafe,
                ),
                Expanded(
                  child: Container(
                    height: 12,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(colors: [kDanger, kDangerDeep]),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
 
TextStyle mono(double size) {
  return TextStyle(
    fontFamily: 'monospace',
    fontSize: size,
    fontWeight: FontWeight.w600,
  );
}
 