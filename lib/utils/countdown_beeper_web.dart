import 'dart:js_interop';

import 'package:web/web.dart' as web;

web.AudioContext? _audioContext;

/// Llama esto desde un gesto del usuario (p. ej. al iniciar sesión) para
/// crear y desbloquear el AudioContext antes de que suenen los pitidos.
void primeAudioContext() {
  _audioContext ??= web.AudioContext();
  if (_audioContext!.state == 'suspended') {
    _audioContext!.resume();
  }
}

Future<void> playCountdownBeep({bool isFinal = false}) async {
  final context = _audioContext ??= web.AudioContext();

  if (context.state == 'suspended') {
    await context.resume().toDart;
  }

  final oscillator = context.createOscillator();
  final gain = context.createGain();

  // Pitido corto (3s, 2s restantes) vs pitido largo final (1s restante)
  oscillator.type = 'square';
  oscillator.frequency.value = isFinal ? 1100 : 880;
  gain.gain.value = 0.055;

  oscillator.connect(gain);
  gain.connect(context.destination);

  final now = context.currentTime;
  final duration = isFinal ? 0.45 : 0.13;
  oscillator.start(now);
  oscillator.stop(now + duration);
}

Future<void> playCountdownFinishBeep() async {
  final context = _audioContext ??= web.AudioContext();

  if (context.state == 'suspended') {
    await context.resume().toDart;
  }

  // Triple pitido corto para marcar fin del temporizador.
  const starts = [0.00, 0.09, 0.18];
  for (final offset in starts) {
    final oscillator = context.createOscillator();
    final gain = context.createGain();

    oscillator.type = 'square';
    oscillator.frequency.value = 1250;
    gain.gain.value = 0.06;

    oscillator.connect(gain);
    gain.connect(context.destination);

    final startAt = context.currentTime + offset;
    oscillator.start(startAt);
    oscillator.stop(startAt + 0.07);
  }
}
