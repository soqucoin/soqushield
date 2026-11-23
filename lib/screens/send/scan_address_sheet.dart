// The send screen's scanner: a sheet with the camera in it that reads one
// Soqucoin address out of a QR code and hands it back to the screen that
// opened it, or nothing when the person backs out.
//
// What a code may carry is decided by AddressScan (lib/services/
// address_scan.dart): an address, bare or behind the soqucoin: scheme, and no
// amount or label. A code the parser refuses leaves its reason on the sheet
// and the camera keeps looking; the first accepted address closes the sheet.
// The camera stops when the app leaves the foreground and starts again when
// it returns (the scanner widget's own lifecycle handling), and the sheet is a
// pageless route under the screen that raised it, so a lock that routes away
// takes the sheet down with that screen.
//
// On the web the send screen offers no scanner: the web decoder is fetched
// from a content network at run time, which this app does not do.
//
// Copyright 2026 Soqucoin Labs Inc.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/wallet_keys.dart';
import '../../services/address_scan.dart';
import '../../theme/instrument.dart';
import '../../theme/motion.dart';
import '../shell.dart';

/// Opens a scanner over [context] and completes with an address accepted for
/// [network] (either network when null), or null when none was read.
typedef ScanAddress = Future<String?> Function(
    BuildContext context, SoqNetwork? network);

/// How the send screen opens the scanner. The default raises the camera
/// sheet; a test substitutes a function that answers at once.
final scanAddressProvider = Provider<ScanAddress>((_) => showScanAddressSheet);

/// The camera sheet, on the root navigator so it covers the shell's tab bar.
Future<String?> showScanAddressSheet(
        BuildContext context, SoqNetwork? network) =>
    showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: kShellMaxWidth),
      backgroundColor: Instrument.void0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.zero,
        side: BorderSide(color: Instrument.lineHi, width: 0.6),
      ),
      builder: (_) => ScanAddressSheet(network: network),
    );

/// What the sheet puts in the picture: by default the scanner widget over the
/// camera; a test hands in a stand-in that calls [onRaw] with a code's text.
typedef ScanCameraBuilder = Widget Function(
    BuildContext context, void Function(String raw) onRaw);

class ScanAddressSheet extends StatefulWidget {
  /// The network an address must belong to; null takes either.
  final SoqNetwork? network;

  /// The camera, replaceable: a widget test cannot start one.
  @visibleForTesting
  final ScanCameraBuilder? camera;

  const ScanAddressSheet({super.key, required this.network, this.camera});

  /// The line under the picture until a code is refused.
  static const hint = 'Point the camera at a Soqucoin address QR code. '
      'Nothing but the address is read.';

  @override
  State<ScanAddressSheet> createState() => _ScanAddressSheetState();
}

class _ScanAddressSheetState extends State<ScanAddressSheet> {
  /// One format, and a code reported once until a different one is seen, so
  /// a refused code's reason stays put instead of flickering every frame.
  late final MobileScannerController? _camera = widget.camera == null
      ? MobileScannerController(
          formats: const [BarcodeFormat.qrCode],
          detectionSpeed: DetectionSpeed.noDuplicates,
        )
      : null;

  String? _refusal;
  bool _done = false;

  @override
  void dispose() {
    unawaited(_camera?.dispose());
    super.dispose();
  }

  /// One code's text, from the camera or from a test. The first accepted
  /// address closes the sheet; a refused code leaves its reason and the
  /// camera keeps looking.
  void _onRaw(String raw) {
    if (_done || !mounted) return;
    // A detection can land after the sheet is dismissed, while its route is
    // still animating out. Nothing under the sheet may be popped in its
    // place, so a sheet that is no longer the current route reads nothing.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      _done = true;
      return;
    }
    final scan = AddressScan.parse(raw, widget.network);
    if (scan.accepted) {
      _done = true;
      HapticFeedback.mediumImpact();
      Navigator.of(context).pop(scan.address);
      return;
    }
    if (scan.error != _refusal) setState(() => _refusal = scan.error);
  }

  void _onDetect(BarcodeCapture capture) {
    for (final code in capture.barcodes) {
      if (_done) return;
      final raw = code.rawValue;
      if (raw != null) _onRaw(raw);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // The picture is square, as wide as the sheet allows and never more than
    // half the screen tall, so the lines under it stay on a short phone.
    final side = math.min(size.width - 44, size.height * 0.5);
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _top(context),
          const SizedBox(height: 10),
          SizedBox(width: side, height: side, child: _picture()),
          const SizedBox(height: 20),
          _line(),
          const SizedBox(height: 14),
          SizedBox(height: 36, child: Center(child: _torch())),
          const SizedBox(height: 18),
        ],
      ),
    );
  }

  Widget _top(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 8, 0),
        child: Row(
          children: [
            Expanded(
                child: Text('SCAN ADDRESS', style: Instrument.eyebrow(size: 11))),
            IconButton(
              key: const Key('scan-close'),
              tooltip: 'Close',
              icon: const Icon(Icons.close_rounded,
                  color: Instrument.label, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );

  Widget _picture() {
    final camera = widget.camera;
    final picture = camera != null
        ? camera(context, _onRaw)
        : MobileScanner(
            controller: _camera,
            onDetect: _onDetect,
            placeholderBuilder: (_) => const ColoredBox(color: Instrument.void2),
            errorBuilder: (_, error) => _CameraUnavailable(error.errorCode),
          );
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        ClipRect(child: picture),
        // The brackets Receive puts around its QR, here around the picture:
        // drawn outside it, so nothing sits over the code the camera reads.
        const IgnorePointer(child: CustomPaint(painter: _FramePainter())),
      ],
    );
  }

  Widget _line() {
    final refusal = _refusal;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Text(
        refusal ?? ScanAddressSheet.hint,
        key: const Key('scan-line'),
        textAlign: TextAlign.center,
        style: TextStyle(
            color: refusal == null ? Instrument.faint : Instrument.threat,
            fontSize: 11.5,
            height: 1.5),
      ),
    );
  }

  /// The light, while the camera runs and has one. Its slot is reserved
  /// either way, so the sheet does not jump as the camera starts.
  Widget _torch() {
    final camera = _camera;
    if (camera == null) return const SizedBox.shrink();
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: camera,
      builder: (_, state, _) {
        if (!state.isRunning ||
            state.torchState == TorchState.unavailable) {
          return const SizedBox.shrink();
        }
        final on = state.torchState == TorchState.on;
        return InstrumentActionChip(
          label: on ? 'Light off' : 'Light on',
          icon: on ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded,
          onTap: () => unawaited(camera.toggleTorch()),
        );
      },
    );
  }
}

/// The picture when there is no camera to show: the permission is off, the
/// device has none, or it could not be started.
class _CameraUnavailable extends StatelessWidget {
  final MobileScannerErrorCode code;
  const _CameraUnavailable(this.code);

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Instrument.void2,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              switch (code) {
                MobileScannerErrorCode.permissionDenied =>
                  'Camera access is off. Allow it for SoquShield in your '
                      'phone\'s settings, then open the scanner again.',
                MobileScannerErrorCode.unsupported =>
                  'This device has no camera the scanner can use.',
                _ => 'The camera could not be started.',
              },
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Instrument.label, fontSize: 12, height: 1.5),
            ),
          ),
        ),
      );
}

/// The resting frame of the Receive screen's lock-on, around the picture.
class _FramePainter extends CustomPainter {
  const _FramePainter();

  @override
  void paint(Canvas canvas, Size size) => paintBrackets(
      canvas, Offset.zero & size, 8, 14, 0.7,
      color: Instrument.signalDim);

  @override
  bool shouldRepaint(covariant _FramePainter old) => false;
}
