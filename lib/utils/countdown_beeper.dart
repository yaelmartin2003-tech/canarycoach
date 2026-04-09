import 'countdown_beeper_stub.dart'
    if (dart.library.html) 'countdown_beeper_web.dart'
    as impl;

void primeAudioContext() => impl.primeAudioContext();

void playCountdownBeep({bool isFinal = false}) =>
    impl.playCountdownBeep(isFinal: isFinal);

void playCountdownFinishBeep() => impl.playCountdownFinishBeep();
