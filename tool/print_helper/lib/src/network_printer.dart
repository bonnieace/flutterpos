/// Network printers: the raw socket a browser cannot open.
///
/// **The Android app's own route**, from this computer instead: connect to the
/// printer's address and port, hand it the ESC/POS bytes, close. The codes are
/// the ones the app's `dart:io` transport uses, so a till reads the same
/// sentence whichever device sent the receipt.
library;

import 'dart:async';
import 'dart:io';

import 'protocol.dart';

/// Resolves [target] to an address on this shop's own network, or throws a
/// [HelperCode] string.
Future<InternetAddress> _resolve(NetworkTarget target) async {
  final literal = InternetAddress.tryParse(target.host);
  final List<InternetAddress> addresses;
  try {
    addresses = literal == null
        ? await InternetAddress.lookup(target.host)
        : <InternetAddress>[literal];
  } on SocketException {
    throw HelperCode.unreachable;
  }
  if (addresses.isEmpty) throw HelperCode.unreachable;
  // Every answer must be local: a name that resolves anywhere public is not a
  // printer in this shop, whatever else it might be.
  if (!addresses.every(isLocalAddress)) throw HelperCode.refused;
  return addresses.first;
}

Future<Socket> _connect(NetworkTarget target, Duration connectTimeout) async {
  final address = await _resolve(target);
  final started = DateTime.now();
  try {
    return await Socket.connect(address, target.port, timeout: connectTimeout);
  } on SocketException {
    // The elapsed clock decides, not an error number, which differs by
    // platform - the reason the app's own transport gives.
    throw DateTime.now().difference(started) >= connectTimeout
        ? HelperCode.connectTimeout
        : HelperCode.unreachable;
  }
}

/// Sends [bytes] to [target]. Null when every byte was handed off, otherwise a
/// [HelperCode].
Future<String?> sendNetworkPrinter(
  NetworkTarget target,
  List<int> bytes, {
  Duration connectTimeout = const Duration(seconds: 5),
  Duration writeTimeout = const Duration(seconds: 10),
}) async {
  final Socket socket;
  try {
    socket = await _connect(target, connectTimeout);
  } on String catch (code) {
    return code;
  }
  try {
    socket.add(bytes);
    await socket.flush().timeout(writeTimeout);
    await socket.close().timeout(writeTimeout);
    return null;
  } on TimeoutException {
    return HelperCode.writeTimeout;
  } on SocketException {
    return HelperCode.unreachable;
  } finally {
    socket.destroy();
  }
}

/// Connects to [target] and lets go, without printing.
Future<String?> probeNetworkPrinter(
  NetworkTarget target, {
  Duration connectTimeout = const Duration(seconds: 5),
}) async {
  try {
    (await _connect(target, connectTimeout)).destroy();
    return null;
  } on String catch (code) {
    return code;
  }
}
