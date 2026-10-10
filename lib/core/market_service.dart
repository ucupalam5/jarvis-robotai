import 'dart:convert';

import 'package:http/http.dart' as http;

/// Skill TradingView: harga pasar real-time via API publik GRATIS (tanpa key).
/// - Kripto: Binance public API (https://api.binance.com)
/// - Saham Indonesia: Stooq free CSV (https://stooq.com), suffix .jk
///
/// Dipakai perintah suara "harga bitcoin berapa?" dan function calling AI.
class MarketService {
  /// Kata kunci Indonesia -> pair Binance.
  static const Map<String, String> cryptoMap = {
    'bitcoin': 'BTCUSDT',
    'btc': 'BTCUSDT',
    'ethereum': 'ETHUSDT',
    'eth': 'ETHUSDT',
    'etherium': 'ETHUSDT',
    'bnb': 'BNBUSDT',
    'binance': 'BNBUSDT',
    'solana': 'SOLUSDT',
    'sol': 'SOLUSDT',
    'xrp': 'XRPUSDT',
    'ripple': 'XRPUSDT',
    'dogecoin': 'DOGEUSDT',
    'doge': 'DOGEUSDT',
    'cardano': 'ADAUSDT',
    'ada': 'ADAUSDT',
    'tron': 'TRXUSDT',
    'trx': 'TRXUSDT',
    'toncoin': 'TONUSDT',
    'ton': 'TONUSDT',
    'shiba': 'SHIBUSDT',
    'shib': 'SHIBUSDT',
    'avalanche': 'AVAXUSDT',
    'avax': 'AVAXUSDT',
    'chainlink': 'LINKUSDT',
    'link': 'LINKUSDT',
    'polkadot': 'DOTUSDT',
    'dot': 'DOTUSDT',
    'polygon': 'MATICUSDT',
    'matic': 'MATICUSDT',
    'litecoin': 'LTCUSDT',
    'ltc': 'LTCUSDT',
    'arbitrum': 'ARBUSDT',
    'arb': 'ARBUSDT',
    'optimism': 'OPUSDT',
    'op': 'OPUSDT',
    'sui': 'SUIUSDT',
    'aptos': 'APTUSDT',
    'apt': 'APTUSDT',
    'near': 'NEARUSDT',
    'cosmos': 'ATOMUSDT',
    'atom': 'ATOMUSDT',
    'pepe': 'PEPEUSDT',
    'render': 'RENDERUSDT',
    'ondo': 'ONDOUSDT',
    'jupiter': 'JUPUSDT',
    'jup': 'JUPUSDT',
  };

  /// Format USD ala Indonesia untuk TTS: 82700 -> "82.700 dolar".
  static String _usd(double v) {
    if (v == 0) return '0 dolar';
    String s;
    if (v >= 1000) {
      s = v.toStringAsFixed(0);
    } else if (v >= 1) {
      s = v.toStringAsFixed(2);
    } else {
      s = v.toStringAsFixed(6);
    }
    // Pemisah ribuan titik (Indonesia), desimal koma.
    final parts = s.split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m.group(1)}.');
    final dec = parts.length > 1
        ? ',${parts[1].replaceAll(RegExp(r'0+$'), '')}'
        : '';
    final decClean = dec == ',' ? '' : dec;
    return '$intPart$decClean dolar';
  }

  /// Harga kripto + perubahan 24 jam. Return string siap ucap, '' bila gagal.
  static Future<String> cryptoPrice(String keyword) async {
    final sym = cryptoMap[keyword.toLowerCase().trim()];
    if (sym == null) return '';
    try {
      final pRes = await http
          .get(Uri.parse('https://api.binance.com/api/v3/ticker/price?symbol=$sym'))
          .timeout(const Duration(seconds: 10));
      if (pRes.statusCode != 200) return '';
      final price =
          double.tryParse(jsonDecode(pRes.body)['price'].toString()) ?? 0;
      double chg = 0;
      try {
        final cRes = await http
            .get(Uri.parse('https://api.binance.com/api/v3/ticker/24hr?symbol=$sym'))
            .timeout(const Duration(seconds: 10));
        if (cRes.statusCode == 200) {
          chg = double.tryParse(
                  jsonDecode(cRes.body)['priceChangePercent'].toString()) ??
              0;
        }
      } catch (_) {}
      final nama = keyword.toLowerCase() == 'btc'
          ? 'Bitcoin'
          : keyword.toLowerCase() == 'eth'
              ? 'Ethereum'
              : keyword[0].toUpperCase() + keyword.substring(1);
      final arah = chg >= 0 ? 'naik' : 'turun';
      final chgTxt = '${chg.abs().toStringAsFixed(2).replaceAll('.', ',')} persen';
      return 'Harga $nama ${_usd(price)}, $arah $chgTxt dalam 24 jam terakhir, Sir.';
    } catch (_) {
      return '';
    }
  }

  /// Cari kata kunci kripto di dalam kalimat. Return keyword atau ''.
  static String findCrypto(String text) {
    final t = ' ${text.toLowerCase()} ';
    // Urutkan kunci terpanjang dulu agar "bitcoin" menang atas "bit".
    final keys = cryptoMap.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      if (t.contains(' $k ') || t.contains(' $k,') || t.endsWith(' $k')) {
        return k;
      }
    }
    return '';
  }

  /// Harga saham Indonesia (IDX) via Stooq. [ticker]: mis. "BBCA".
  /// Return string siap ucap, '' bila gagal.
  static Future<String> stockPrice(String ticker) async {
    final t = ticker.toUpperCase().trim();
    if (t.isEmpty) return '';
    try {
      final res = await http
          .get(Uri.parse(
              'https://stooq.com/q/l/?s=${t.toLowerCase()}.jk&f=sd2t2ohlcv&h&e=csv'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return '';
      // Format CSV: Symbol,Date,Time,Open,High,Low,Close,Volume
      final lines = res.body.trim().split('\n');
      if (lines.length < 2) return '';
      final cols = lines[1].split(',');
      if (cols.length < 7) return '';
      final close = double.tryParse(cols[6]) ?? 0;
      final prevClose = double.tryParse(cols[3]) ?? 0;
      if (close <= 0) return '';
      final rupiah = 'Rp${close.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m.group(1)}.')}';
      var chgTxt = '';
      if (prevClose > 0) {
        final chg = (close - prevClose) / prevClose * 100;
        final arah = chg >= 0 ? 'naik' : 'turun';
        chgTxt =
            ', $arah ${chg.abs().toStringAsFixed(2).replaceAll('.', ',')} persen dari pembukaan';
      }
      return 'Saham $t $rupiah per lembar$chgTxt, Sir.';
    } catch (_) {
      return '';
    }
  }
}
