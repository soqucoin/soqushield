// Transaction ids as the node and the history service write them.
//
// Copyright 2026 Soqucoin Labs Inc.

final _txid = RegExp(r'^[0-9a-fA-F]{64}$');

/// Whether [s] is a transaction id: exactly 64 hex characters. Ids reach the
/// app from remote services (the history service, the node's reply to a
/// broadcast), so one is checked before it becomes part of a request path or
/// a link.
bool isTxid(String s) => _txid.hasMatch(s);
