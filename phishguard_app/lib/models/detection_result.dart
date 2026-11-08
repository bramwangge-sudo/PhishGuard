import 'package:flutter/material.dart';
import '../constants/app_colors.dart';

const double kWarnThreshold = 0.5; // >= 50% -> Mencurigakan
const double kPhishThreshold = 0.8; // >= 80% -> Phishing

enum VerdictLevel { safe, suspicious, phishing }

class VerdictStyle {
  final String label;
  final String headline;
  final String advice;
  final Color fg;
  final Color bg;
  final IconData icon;

  const VerdictStyle({
    required this.label,
    required this.headline,
    required this.advice,
    required this.fg,
    required this.bg,
    required this.icon,
  });
}

const Map<VerdictLevel, VerdictStyle> kVerdictStyles = {
  VerdictLevel.safe: VerdictStyle(
    label: 'Kemungkinan aman',
    headline: 'Tidak ada pola phishing yang menonjol.',
    advice:
        'Tetap periksa ejaan alamat sebelum memasukkan data, karena hasil ini hanya berdasarkan pola URL.',
    fg: Color(0xFF0B6B4D),
    bg: Color(0xFFE3F4EC),
    icon: Icons.verified_user_outlined,
  ),
  VerdictLevel.suspicious: VerdictStyle(
    label: 'Mencurigakan',
    headline: 'Pola URL mirip phishing, tetapi belum pasti.',
    advice:
        'Pastikan alamat ini berasal dari sumber resmi sebelum memasukkan akun atau kata sandi.',
    fg: Color(0xFF8A5200),
    bg: Color(0xFFFFF1D1),
    icon: Icons.warning_amber_rounded,
  ),
  VerdictLevel.phishing: VerdictStyle(
    label: 'Terindikasi phishing',
    headline: 'URL ini memiliki banyak pola phishing.',
    advice:
        'Jangan memasukkan kata sandi atau data pribadi. Laporkan alamat ini ke penyedia layanan yang ditiru.',
    fg: Color(0xFFA3231B),
    bg: Color(0xFFFDE8E6),
    icon: Icons.gpp_bad_outlined,
  ),
};

enum Tendency { phishing, neutral, legitimate }

class TendencyStyle {
  final String text;
  final Color fg;
  final Color bg;
  const TendencyStyle(this.text, this.fg, this.bg);
}

const Map<Tendency, TendencyStyle> kTendencyStyles = {
  Tendency.phishing:
      TendencyStyle('Condong phishing', Color(0xFFA3231B), Color(0xFFFDE8E6)),
  Tendency.neutral:
      TendencyStyle('Netral', Color(0xFF3A4854), Color(0xFFEBEFF2)),
  Tendency.legitimate: TendencyStyle(
      'Condong legitimate', Color(0xFF0B6B4D), Color(0xFFE3F4EC)),
};

class FeatureItem {
  final String name;
  final String value;
  final Tendency tendency;

  const FeatureItem({
    required this.name,
    required this.value,
    required this.tendency,
  });

  factory FeatureItem.fromJson(Map<String, dynamic> j) {
    // Disesuaikan dengan key dari FastAPI: 'tendency', 'name', 'value'
    final raw = (j['tendency'] ?? '').toString().toLowerCase();
    Tendency t = Tendency.neutral;
    if (raw.startsWith('phish')) t = Tendency.phishing;
    if (raw.startsWith('legit')) t = Tendency.legitimate;
    
    return FeatureItem(
      name: (j['name'] ?? '').toString(),
      value: (j['value'] ?? '').toString(),
      tendency: t,
    );
  }
}

class DetectionResult {
  final String url;
  final double probPhishing;
  final int treeVotes;
  final int totalTrees;
  final int featureCount;
  final List<FeatureItem> features;

  const DetectionResult({
    required this.url,
    required this.probPhishing,
    required this.treeVotes,
    required this.totalTrees,
    required this.featureCount,
    required this.features,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> j) {
    final rawFeatures = j['features'];
    return DetectionResult(
      url: (j['url'] ?? '').toString(),
      // Disesuaikan dengan key dari FastAPI: 'probPhishing', 'treeVotes', 'totalTrees', 'featureCount'
      probPhishing: (j['probPhishing'] as num?)?.toDouble() ?? 0.0,
      treeVotes: (j['treeVotes'] as num?)?.toInt() ?? 0,
      totalTrees: (j['totalTrees'] as num?)?.toInt() ?? 42,
      featureCount: (j['featureCount'] as num?)?.toInt() ?? 42,
      features: rawFeatures is List
          ? rawFeatures
              .whereType()
              .map((m) => FeatureItem.fromJson(Map<String, dynamic>.from(m)))
              .toList()
          : const [],
    );
  }

  VerdictLevel get level {
    final p = probPhishing;
    if (p >= kPhishThreshold) return VerdictLevel.phishing;
    if (p >= kWarnThreshold) return VerdictLevel.suspicious;
    return VerdictLevel.safe;
  }
}

class SampleUrl {
  final String label;
  final String url;
  const SampleUrl(this.label, this.url);
}

const List<SampleUrl> kSamples = [
  SampleUrl('Portal kampus (.ac.id)', 'https://elearning.bsi.ac.id/login'),
  SampleUrl('Login palsu',
      'http://secure-login-bank.verifikasi-akun.xyz/update?id=8841'),
  SampleUrl('Profil kampus', 'https://www.contoh-kampus.ac.id/profil'),
];