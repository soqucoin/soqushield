/// What a scanned QR code may hand the send screen: one Soqucoin address.
///
/// A code carries the bare address, which is what the Receive screen encodes
/// and what the public help text promises, or the address behind the
/// `soqucoin:` scheme a payment link would use. Nothing else is read. An
/// `amount` or a `label` after the address is dropped unread: the amount is
/// the owner's to type and to approve on the send screen, and a label is a
/// line of text a hostile code would use to pass itself off as someone else.
///
/// TODO(eltoo): the payload will probably change once eltoo channels land.
/// A code would then carry a channel payload beside, or instead of, the
/// on-chain address, and this parser, the Receive QR
/// (lib/screens/receive/receive_pilot_screen.dart) and the payload pin in
/// test/lite_scope_test.dart change together.
///
/// Copyright 2026 Soqucoin Labs Inc.
library;

import 'package:flutter/foundation.dart';

import '../models/wallet_keys.dart';
import 'tx_builder.dart';

@immutable
class AddressScan {
  const AddressScan._({this.address, this.error});

  /// The accepted address in the lowercase form the rest of the app uses,
  /// or null when the code is refused.
  final String? address;

  /// Why the code is refused, in the words the send screen shows, or null
  /// when [address] is set.
  final String? error;

  bool get accepted => address != null;

  /// The scheme a payment link puts in front of the address.
  static const scheme = 'soqucoin:';

  /// The one line shown for a code that is not shaped like an address at
  /// all: a web link, a sentence, another coin's address. The validator's
  /// own messages echo part of what they were handed, and a code written to
  /// be scanned by a wallet must not get to put its own words on the screen.
  static const notAnAddress = 'That code is not a Soqucoin address';

  /// Read [raw], the text of a scanned code, as an address on [network], or
  /// on whichever network its prefix names when [network] is null: the send
  /// screen names the wallet's network, the address book takes either.
  static AddressScan parse(String raw, SoqNetwork? network) {
    var text = raw.trim();
    if (text.toLowerCase().startsWith(scheme)) {
      text = text.substring(scheme.length);
      if (text.startsWith('//')) text = text.substring(2);
      final query = text.indexOf('?');
      if (query >= 0) text = text.substring(0, query);
      text = text.trim();
    }
    // Only a string whose human-readable part, everything before the last
    // separator, is one of the app's networks reaches the validator. The
    // other network's address goes through so the validator can say which
    // network it belongs to. The prefix alone is not enough: a code can put
    // one in front of its own words ("sq1call us now1qqqqqqq"), and the
    // validator, which reads the part before the LAST separator, would then
    // read those words back as an unknown prefix. SoqNetwork.ofAddress
    // applies that rule.
    final own = SoqNetwork.ofAddress(text);
    if (own == null) return const AddressScan._(error: notAnAddress);
    // Bech32m allows an all-uppercase spelling, and a QR code's alphanumeric
    // mode encodes one in fewer modules; it is the same address, carried on
    // in the lowercase form. A mixed-case spelling is left as it is, for the
    // validator to refuse.
    final candidate = text == text.toUpperCase() ? text.toLowerCase() : text;
    final refusal = TxBuilder.validateAddress(candidate, network ?? own);
    if (refusal != null) return AddressScan._(error: refusal);
    return AddressScan._(address: candidate);
  }
}
