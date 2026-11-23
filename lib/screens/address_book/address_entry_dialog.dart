// Save an address under a name, or rename a saved one.
//
// The dialog talks to the book itself: a refusal (a blank name, an address
// that does not validate, a duplicate) stays under the field with the
// book's own words, and the dialog closes only on a saved entry or a cancel.
// The address can be typed, pasted or scanned; whichever way it arrives, the
// book validates it before anything is stored.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/address_book_entry.dart';
import '../../providers/address_book_provider.dart';
import '../../theme/instrument.dart';
import '../send/scan_address_sheet.dart';

/// Opens the dialog over [context]. With [rename], the entry's address is
/// shown and only its name is taken; otherwise a name and an address, the
/// address field starting as [initialAddress]. Completes with the saved
/// entry, or null.
Future<AddressBookEntry?> showAddressEntryDialog(
  BuildContext context, {
  String initialAddress = '',
  AddressBookEntry? rename,
}) =>
    showDialog<AddressBookEntry>(
      context: context,
      builder: (_) =>
          AddressEntryDialog(initialAddress: initialAddress, rename: rename),
    );

class AddressEntryDialog extends ConsumerStatefulWidget {
  final String initialAddress;
  final AddressBookEntry? rename;
  const AddressEntryDialog({
    super.key,
    this.initialAddress = '',
    this.rename,
  });

  @override
  ConsumerState<AddressEntryDialog> createState() => _AddressEntryDialogState();
}

class _AddressEntryDialogState extends ConsumerState<AddressEntryDialog> {
  // ⛔ The dialog owns its controllers and disposes them here: the route is
  // still animating out when the caller gets its result.
  late final TextEditingController _name =
      TextEditingController(text: widget.rename?.name ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.initialAddress);

  String? _refusal;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _refusal = null;
    });
    final route = ModalRoute.of(context);
    final book = ref.read(addressBookProvider.notifier);
    final rename = widget.rename;
    try {
      final entry = rename != null
          ? await book.rename(rename.id, _name.text)
          : await book.add(name: _name.text, address: _address.text);
      if (!mounted) return;
      HapticFeedback.selectionClick();
      // The dialog may have been dismissed while the write was in flight
      // and still be animating out. Popping then would take the route
      // under it. The entry is saved either way, and the book's state
      // already shows it.
      if (route == null || !route.isCurrent) return;
      Navigator.of(context).pop(entry);
    } on AddressBookRefusal catch (e) {
      if (!mounted) return;
      setState(() {
        _refusal = e.message;
        _busy = false;
      });
    } catch (e) {
      debugPrint('AddressBook: write failed: $e');
      if (!mounted) return;
      setState(() {
        _refusal = 'The address book could not be written';
        _busy = false;
      });
    }
  }

  Future<void> _paste() async {
    if (_busy) return;
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    setState(() {
      if (text.isEmpty) {
        _refusal = 'The clipboard holds no text';
      } else {
        _address.text = text;
        _refusal = null;
      }
    });
  }

  /// The scanner, for either network: the book keeps both, and the entry's
  /// network is read off the address.
  Future<void> _scan() async {
    // Not over a save in flight: the scanner's sheet would then sit above
    // this dialog when the save came to pop it.
    if (_busy) return;
    final scan = ref.read(scanAddressProvider);
    final address = await scan(context, null);
    if (!mounted || address == null) return;
    setState(() {
      _address.text = address;
      _refusal = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rename = widget.rename;
    final refusal = _refusal;
    return InstrumentPanel(
      title: rename == null ? 'SAVE AN ADDRESS' : 'RENAME',
      actions: [
        InstrumentDialogAction(
            label: 'CANCEL',
            onPressed: _busy ? null : () => Navigator.of(context).pop()),
        InstrumentDialogAction(
            label: 'SAVE', primary: true, onPressed: _busy ? null : _save),
      ],
      children: [
        _Field(
          key: const Key('entry-name'),
          controller: _name,
          hint: 'Name',
          maxLength: AddressBookEntry.maxNameLength,
          autofocus: true,
        ),
        const SizedBox(height: 12),
        if (rename != null)
          Text(rename.address,
              style: const TextStyle(
                  color: Instrument.label,
                  fontSize: 11,
                  fontFamily: kMono,
                  height: 1.5))
        else ...[
          _Field(
            key: const Key('entry-address'),
            controller: _address,
            hint: 'sq1… or ssq1… address',
            mono: true,
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              InstrumentActionChip(
                  key: const Key('entry-paste'),
                  label: 'Paste',
                  icon: Icons.content_paste_rounded,
                  onTap: _paste),
              if (!kIsWeb) ...[
                const SizedBox(width: 8),
                InstrumentActionChip(
                    key: const Key('entry-scan'),
                    label: 'Scan',
                    icon: Icons.qr_code_scanner_rounded,
                    onTap: _scan),
              ],
            ],
          ),
        ],
        if (refusal != null) ...[
          const SizedBox(height: 10),
          Text(refusal,
              key: const Key('entry-refusal'),
              style: const TextStyle(
                  color: Instrument.threat, fontSize: 11.5, height: 1.4)),
        ],
        const SizedBox(height: 10),
        Text(
            'Saved on this device only. Not part of the recovery phrase or '
            'the backup.',
            style: TextStyle(color: Instrument.faint, fontSize: 11)),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    super.key,
    required this.controller,
    required this.hint,
    this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.mono = false,
  });
  final TextEditingController controller;
  final String hint;
  final int? maxLength;
  final int maxLines;
  final bool autofocus;
  final bool mono;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        autofocus: autofocus,
        maxLength: maxLength,
        maxLines: maxLines,
        // An address is not a word: no correction may touch it.
        autocorrect: !mono,
        enableSuggestions: !mono,
        style: TextStyle(
            color: Instrument.readout,
            fontSize: mono ? 12.5 : 14,
            fontFamily: mono ? kMono : null),
        decoration: InputDecoration(
          hintText: hint,
          counterText: '',
          hintStyle: TextStyle(color: Instrument.faint, fontSize: 13),
          enabledBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Instrument.line),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.zero,
            borderSide: BorderSide(color: Instrument.signal),
          ),
        ),
      );
}
