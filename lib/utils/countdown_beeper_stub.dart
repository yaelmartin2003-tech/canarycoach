import 'package:flutter/services.dart';

void primeAudioContext() {}

void playCountdownBeep({bool isFinal = false}) {
  SystemSound.play(SystemSoundType.alert);
}

void playCountdownFinishBeep() {
  SystemSound.play(SystemSoundType.alert);
  Future<void>.delayed(
    const Duration(milliseconds: 90),
    () => SystemSound.play(SystemSoundType.alert),
  );
  Future<void>.delayed(
    const Duration(milliseconds: 180),
    () => SystemSound.play(SystemSoundType.alert),
  );
}
