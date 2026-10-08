import 'dart:typed_data';
import 'package:convert/convert.dart';

/// One parsed input: which previous output it spends.
class ParsedTxIn {
  final String prevTxid; // display order (big-endian hex)
  final int prevVout;
  const ParsedTxIn(this.prevTxid, this.prevVout);
}

/// One parsed output: value and locking script.
class ParsedTxOut {
  final int valueSat;
  final Uint8List scriptPubKey;
  const ParsedTxOut(this.valueSat, this.scriptPubKey);
}

class ParsedTx {
  final List<ParsedTxIn> inputs;
  final List<ParsedTxOut> outputs;
  const ParsedTx(this.inputs, this.outputs);
}

/// Minimal Soqucoin transaction parser — the reverse of TxBuilder's
/// serialization (v2, optional segwit marker/flag, byte-less Phase-4 CTxOut).
/// Parses only what history reconstruction needs: input prevouts and outputs.
/// Witness data and locktime are not decoded.
class TxParser {
  static ParsedTx parse(String rawHex) {
    final b = Uint8List.fromList(hex.decode(rawHex));
    var o = 0;

    int u32() {
      final v = b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
      o += 4;
      return v;
    }

    int u64() {
      var v = 0;
      for (var i = 7; i >= 0; i--) {
        v = (v << 8) | b[o + i];
      }
      o += 8;
      return v;
    }

    int varint() {
      final first = b[o++];
      if (first < 0xfd) return first;
      if (first == 0xfd) {
        final v = b[o] | (b[o + 1] << 8);
        o += 2;
        return v;
      }
      if (first == 0xfe) return u32();
      return u64();
    }

    u32(); // version

    // Segwit marker (0x00) + flag (non-zero): a legacy tx can't have zero
    // inputs, so byte[4] == 0 unambiguously means "marker".
    if (b[o] == 0x00 && b[o + 1] != 0x00) {
      o += 2;
    }

    final nIn = varint();
    final inputs = <ParsedTxIn>[];
    for (var i = 0; i < nIn; i++) {
      final txidBytes = b.sublist(o, o + 32).reversed.toList();
      o += 32;
      final vout = u32();
      final scriptLen = varint();
      o += scriptLen; // scriptSig — not needed
      u32(); // sequence
      inputs.add(ParsedTxIn(hex.encode(txidBytes), vout));
    }

    final nOut = varint();
    final outputs = <ParsedTxOut>[];
    for (var i = 0; i < nOut; i++) {
      final value = u64();
      final scriptLen = varint();
      outputs.add(ParsedTxOut(value, b.sublist(o, o + scriptLen)));
      o += scriptLen;
    }

    return ParsedTx(inputs, outputs);
  }
}
