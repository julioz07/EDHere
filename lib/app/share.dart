import 'package:flutter/services.dart';

/// Abre a folha de partilha do Android com [text] (WhatsApp, email, etc.).
/// Devolve false se não for possível (por exemplo, fora do Android).
Future<bool> shareText(String text, {String? subject}) async {
  try {
    await const MethodChannel('edhere/share').invokeMethod<void>('text', {'text': text, 'subject': subject});
    return true;
  } on PlatformException {
    return false;
  } on MissingPluginException {
    return false;
  }
}
