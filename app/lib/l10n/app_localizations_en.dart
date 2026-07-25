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
  String get confirmSelectOfferTitle => 'Choose this driver?';

  @override
  String confirmSelectOfferMessage(String vehicle, int price, int eta) {
    return '$vehicle · $price₮ · $eta min. Confirming sends this driver your exact pickup point — and your phone number, if you turned sharing on. It cannot be taken back.';
  }

  @override
  String get confirmSelectOfferAction => 'Yes, send it';

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
  String get startTripAction => 'Go to trip';

  @override
  String get viewActiveTripAction => 'Start trip';

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

  @override
  String get tripPhaseEnRouteToPickup => 'Driver is on the way';

  @override
  String get tripPhaseInProgress => 'Trip in progress';

  @override
  String get tripPhaseArrived => 'Arrived';

  @override
  String get markPassengerBoardedAction => 'Passenger boarded';

  @override
  String get endTripAction => 'End trip';

  @override
  String get rateTripTitle => 'Rate this trip';

  @override
  String get submitRatingAction => 'Submit';

  @override
  String get tripReceiptPublished => 'Receipt published';

  @override
  String agreedPriceLabel(int price) {
    return 'Agreed price: $price₮';
  }

  @override
  String get locationPermissionNeededHint =>
      'Location access is needed to track this trip';

  @override
  String get grantLocationPermissionAction => 'Grant permission';

  @override
  String get taximeterTitle => 'Taximeter';

  @override
  String get startMeterAction => 'Start';

  @override
  String get meterDestinationOptionalHint => 'Destination (optional)';

  @override
  String estimatedFareLabel(int mnt) {
    return '≈ $mnt₮';
  }

  @override
  String get estimatedFareApproxLabel => 'approximate';

  @override
  String meterFareLabel(int mnt) {
    return '$mnt₮';
  }

  @override
  String meterRunningDistanceLabel(double km) {
    return '$km km';
  }

  @override
  String meterRunningDurationLabel(int min) {
    return '$min min';
  }

  @override
  String get finishMeterAction => 'Finish';

  @override
  String get meterSummaryTitle => 'Trip total';

  @override
  String get downloadTakhiQrLabel => 'Takhi — ownerless taxi';

  @override
  String get meterTariffFieldLabel => 'Price per km (₮)';

  @override
  String get saveTariffAction => 'Save';

  @override
  String get meterTariffInvalidHint => 'Enter a valid number, e.g. 1000';

  @override
  String meterEditTariffAction(int mnt) {
    return 'Rate: $mnt₮/km — edit';
  }

  @override
  String get startAsMeterAction => 'Taximeter';

  @override
  String get callConnectingLabel => 'Connecting…';

  @override
  String get callViaPhoneAction => 'Call by phone';

  @override
  String get callFailedOfferPhoneLabel => 'In-app call did not connect';

  @override
  String get callEndedLabel => 'Call ended';

  @override
  String get incomingCallLabel => 'Incoming call';

  @override
  String get acceptCallAction => 'Accept';

  @override
  String get declineCallAction => 'Decline';

  @override
  String get startCallAction => 'Call';

  @override
  String get voiceNoteTooLongHint => 'Must be under 10 seconds';

  @override
  String get holdToRecordVoiceNoteHint => 'Press and hold to talk';

  @override
  String get shareTripAction => 'Share trip';

  @override
  String get sosAction => 'SOS';

  @override
  String get emergencyContactPhoneFieldLabel => 'Emergency contact number';

  @override
  String get saveEmergencyContactAction => 'Save';

  @override
  String get locationUnavailableHint => 'Location unavailable';

  @override
  String get sosCallPoliceAction => '102 — Police';

  @override
  String get sosCallAmbulanceAction => '103 — Ambulance';

  @override
  String get sosSendLocationSmsAction => 'SMS your emergency contact';

  @override
  String get sosNoContactHint => 'No emergency contact number saved yet';

  @override
  String get sosAddContactAction => 'Add a number';

  @override
  String get settingsAction => 'Settings';

  @override
  String get phoneShareSettingsTitle => 'Phone number';

  @override
  String get phoneShareOwnPhoneFieldLabel => 'Your phone number';

  @override
  String get phoneShareEnabledToggleLabel =>
      'Send my number to the matched driver/rider';

  @override
  String get savePhoneShareSettingsAction => 'Save';

  @override
  String get voiceNoteReceivedLabel => 'New voice message received';

  @override
  String get playVoiceNoteAction => 'Play';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsDriverProfileMenuLabel => 'Driver profile';

  @override
  String get settingsPhoneShareMenuLabel => 'Phone number';

  @override
  String get settingsLegalNoticeMenuLabel => 'Legal notice';

  @override
  String get driverProfileTitle => 'Driver profile';

  @override
  String get driverProfileNameFieldLabel => 'Name';

  @override
  String get driverProfileCarFieldLabel => 'Car model';

  @override
  String get driverProfileColorFieldLabel => 'Color';

  @override
  String get driverProfilePlateFieldLabel => 'License plate';

  @override
  String get driverProfileKmTariffFieldLabel => 'Per-km tariff (₮/km)';

  @override
  String get saveDriverProfileAction => 'Save';

  @override
  String get driverProfileSavedConfirmation => 'Profile saved';

  @override
  String get meteredOfferToggleLabel => 'Metered (my km-tariff)';

  @override
  String get meteredOfferNoTariffHint =>
      'Set your km-tariff in your profile first';

  @override
  String meteredLiveFareLabel(int mnt) {
    return 'Current fare: $mnt₮';
  }

  @override
  String get meteredFareConfirmTitle => 'Final trip fare';

  @override
  String get meteredFareConfirmAction => 'Confirm';

  @override
  String get meteredFareDeclineAction => 'Decline';

  @override
  String get meteredFareDeclinedHint =>
      'You did not confirm the fare, so no receipt was published';

  @override
  String get legalNoticeTitle => 'Legal notice';

  @override
  String get legalNoticeBody =>
      'Takhi is an ownerless P2P platform. There is no driver vetting. Riders and drivers each bear their own risk.';

  @override
  String get backAction => 'Back';

  @override
  String get backToHomeAction => 'Back to home';

  @override
  String get cancelAction => 'Cancel';

  @override
  String get stayAction => 'Stay';

  @override
  String get leaveAction => 'Leave';

  @override
  String get finishTripAction => 'Finish trip';

  @override
  String get leaveTripTitle => 'Leave the trip?';

  @override
  String get leaveTripMessage =>
      'This ends the active trip: live location and calling stop, and you cannot get back into it. The other side will be notified.';

  @override
  String get leaveMeterTitle => 'Stop the meter?';

  @override
  String get leaveMeterMessage =>
      'Leaving now discards this run\'s distance, time and fare without saving them. Tap \"Finish\" first to record it in your journal.';

  @override
  String get leaveRideRequestTitle => 'Cancel your ride request?';

  @override
  String get leaveRideRequestMessage =>
      'Your published request is withdrawn and the offers you received are lost. Requesting again starts from the beginning.';

  @override
  String get leaveSeedBackupTitle => 'Did you save your recovery words?';

  @override
  String get leaveSeedBackupMessage =>
      'If you don\'t write these 12 words down now, you can never see them again. Lose your phone and your identity is gone for good.';
}
