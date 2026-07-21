// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'Тахь';

  @override
  String get passengerMode => 'Passenger';

  @override
  String get driverMode => 'Driver';

  @override
  String get createIdentity => 'Start fresh';

  @override
  String get restoreIdentity => 'Restore';

  @override
  String get seedBackupTitle => 'Back up your recovery words';

  @override
  String get seedBackupWarning =>
      'Write down these 12 words. If you lose your phone, only these restore you. Never show anyone.';

  @override
  String get iSavedIt => 'I saved it';

  @override
  String get connecting => 'Connecting…';

  @override
  String get connected => 'Connected';

  @override
  String get restoreHint => 'Enter your 12 recovery words, separated by spaces';

  @override
  String get restoreError =>
      'That recovery phrase isn\'t valid. Please check it and try again.';

  @override
  String get createIdentityError =>
      'Couldn\'t create your identity. Please try again.';
}
