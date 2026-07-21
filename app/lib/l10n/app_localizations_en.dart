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

  @override
  String get overwriteIdentityTitle => 'Overwrite your current identity?';

  @override
  String get overwriteIdentityMessage =>
      'Creating a new identity replaces your current private key. If you haven\'t saved its recovery phrase, you won\'t be able to get it back.';

  @override
  String get overwriteIdentityCancel => 'Cancel';

  @override
  String get overwriteIdentityConfirm => 'Yes, continue';

  @override
  String get landmarkHint => 'Landmark note (e.g. white gate)';

  @override
  String get nextStep => 'Continue';

  @override
  String get publishRide => 'Publish';

  @override
  String get priceLabel => 'Offered price (₮, optional)';

  @override
  String get offersWaitingTitle => 'Incoming offers';

  @override
  String offerSummary(int price, int eta) {
    return '$price₮ · $eta min';
  }

  @override
  String get sendOfferAction => 'Send offer';

  @override
  String get offerPriceFieldLabel => 'Price (₮)';

  @override
  String get offerEtaFieldLabel => 'ETA (minutes)';

  @override
  String get offerVehicleFieldLabel => 'Vehicle info';

  @override
  String driverOnTheWay(String vehicle) {
    return '$vehicle is on the way';
  }

  @override
  String get handoffReceivedTitle => 'Passenger\'s exact location';

  @override
  String get startAsPassengerAction => 'Request a ride';

  @override
  String get startAsDriverAction => 'Listen for calls';

  @override
  String get qrNotSetHint => 'You haven\'t added your bank QR yet';

  @override
  String get qrCaptureTitle => 'Bank QR image';

  @override
  String get qrCaptureAction => 'Choose image';

  @override
  String get qrSaveAction => 'Save';

  @override
  String get qrSavedConfirmation => 'QR saved';

  @override
  String get qrSaveError => 'Couldn\'t save the QR. Please try again.';

  @override
  String get payWithQrOrCashHint => 'Scan the driver\'s QR or pay cash';
}
