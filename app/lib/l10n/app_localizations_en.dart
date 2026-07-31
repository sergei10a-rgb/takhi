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
  String get priceLabel => 'Offered price (₮)';

  @override
  String get passengerPickupStepTitle => 'Where are you starting from?';

  @override
  String get passengerPickupStepSubtitle =>
      'Pan the map to put the pin on your pickup point.';

  @override
  String get passengerDestinationStepTitle => 'Where are you going?';

  @override
  String get passengerDestinationStepSubtitle =>
      'Pan the map to put the pin on your destination.';

  @override
  String get passengerPriceStepTitle => 'Name your price?';

  @override
  String get passengerPriceStepSubtitle =>
      'Optional. Leave it empty and drivers will quote their own.';

  @override
  String get offersRankedByReputationHint =>
      'Ranked on trips both sides confirmed';

  @override
  String get offersAllNewHint => 'All new drivers — in the order they answered';

  @override
  String get offersWaitingEmptyTitle => 'Waiting for offers';

  @override
  String get offersWaitingEmptyHint =>
      'Drivers nearby can see your request. Offers show up here as they arrive.';

  @override
  String offerEtaLabel(int eta) {
    return '$eta min';
  }

  @override
  String get offerTopReputationBadge => 'Most trusted';

  @override
  String driverConfirmedTripsLabel(int count) {
    return 'Confirmed trips: $count';
  }

  @override
  String get driverNoConfirmedTripsLabel => 'No confirmed trips yet';

  @override
  String get offerDriverNameUnknown => 'Driver sent no name';

  @override
  String get driverPhotoUnverifiedBadge => 'Unverified photo';

  @override
  String get driverPhotoUnverifiedHint =>
      'The driver\'s phone only checked that a human face is in this picture. Nobody checked that the face is this driver\'s. Compare the face and the plate yourself before you get in.';

  @override
  String get driverPhotoEnlargeSemanticLabel => 'View the photo full screen';

  @override
  String get driverPhotoMissingLabel => 'No photo sent';

  @override
  String get driverPhotoCloseAction => 'Close';

  @override
  String get offerDriverSelectAction => 'Choose this driver';

  @override
  String get passengerDriverOnTheWaySubtitle =>
      'The agreed terms are below. Go to the trip to call your driver and follow the route.';

  @override
  String get offersWaitingTitle => 'Incoming offers';

  @override
  String get confirmSelectOfferTitle => 'Choose this driver?';

  @override
  String confirmSelectOfferMessage(String vehicle, String price, int eta) {
    return '$vehicle · $price ₮ · $eta min. Confirming sends this driver your exact pickup point — and your phone number, if you turned sharing on. It cannot be taken back.';
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
  String get startAsDriverAction => 'Drive';

  @override
  String get homeSheetTitle => 'Where to?';

  @override
  String get homeDestinationPlaceholder => 'Destination';

  @override
  String get homeDestinationSemanticLabel =>
      'Enter your destination and request a ride';

  @override
  String get homePickupLabel => 'Pickup';

  @override
  String get homeCurrentLocationValue => 'Current location';

  @override
  String get homePickupUnknownValue => 'Location not set yet';

  @override
  String get homeLocationDeniedHint => 'Location permission is not granted';

  @override
  String get homeLocateAction => 'Use my location';

  @override
  String get copyPublicKeyAction => 'Copy your public key';

  @override
  String get publicKeyCopiedConfirmation => 'Public key copied';

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
  String get driverBankQrLabel => 'Driver\'s bank QR';

  @override
  String get payWithQrOptionLabel => 'Scan the driver\'s QR';

  @override
  String get payWithCashOptionLabel => 'Pay in cash';

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
  String agreedPriceLabel(String price) {
    return 'Agreed price: $price ₮';
  }

  @override
  String get locationPermissionNeededHint =>
      'Location access is needed to track this trip';

  @override
  String get locationPermissionNeededTitle => 'Location access needed';

  @override
  String get grantLocationPermissionAction => 'Grant permission';

  @override
  String get taximeterTitle => 'Taximeter';

  @override
  String get meterReadyTitle => 'Ready to drive';

  @override
  String get startMeterAction => 'Start';

  @override
  String get meterDestinationOptionalHint => 'Destination (optional)';

  @override
  String get meterDestinationPlaceholder => 'Pick a destination';

  @override
  String get meterDestinationDoneAction => 'Done';

  @override
  String estimatedFareLabel(String mnt) {
    return 'Est. $mnt ₮';
  }

  @override
  String get estimatedFareApproxLabel => 'approximate';

  @override
  String meterFareLabel(String mnt) {
    return '$mnt ₮';
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
  String meterFareBreakdownLabel(double km, String mnt) {
    return '$km km × $mnt ₮/km';
  }

  @override
  String get meterSummaryDistanceFareRow => 'Distance fare';

  @override
  String get meterPaymentTitle => 'Payment';

  @override
  String get downloadTakhiQrLabel => 'Takhi — ownerless taxi';

  @override
  String get meterTariffTitle => 'Set your rate per km';

  @override
  String get meterTariffSubtitle =>
      'The meter charges every kilometre driven at this rate.';

  @override
  String get meterTariffFieldLabel => 'Price per km (₮)';

  @override
  String get saveTariffAction => 'Save';

  @override
  String get meterTariffInvalidHint => 'Enter a valid number, e.g. 1000';

  @override
  String meterEditTariffAction(String mnt) {
    return 'Rate: $mnt ₮/km — edit';
  }

  @override
  String get meterWaitTariffFieldLabel => 'Waiting rate per minute (₮)';

  @override
  String get meterWaitTariffHint =>
      'Charged while stopped in traffic. 0 means waiting is free.';

  @override
  String get meterWaitTariffInvalidHint =>
      'Enter a valid number (for example 300)';

  @override
  String meterEditWaitTariffAction(String mnt) {
    return 'Waiting: $mnt ₮/min — edit';
  }

  @override
  String get meterEstimateExcludesWaitingHint =>
      'Traffic stops add waiting fare on top — the estimate does not include it.';

  @override
  String get meterModeMovingLabel => 'Moving';

  @override
  String get meterModeWaitingLabel => 'Waiting';

  @override
  String get meterModePausedLabel => 'Paused';

  @override
  String meterWaitingTimeLabel(int min) {
    return '$min min waited';
  }

  @override
  String meterWaitingFareLabel(String mnt) {
    return 'Waiting $mnt ₮';
  }

  @override
  String get pauseMeterAction => 'Pause';

  @override
  String get resumeMeterAction => 'Resume';

  @override
  String get pauseMeterConfirmTitle => 'Pause the meter?';

  @override
  String get pauseMeterConfirmMessage =>
      'While paused neither distance nor waiting is charged. Tap Resume to start it again.';

  @override
  String get meterSummaryWaitingFareRow => 'Waiting fare';

  @override
  String get meterSummaryWaitingDurationRow => 'Time waited';

  @override
  String get meterSummaryTotalRow => 'Total';

  @override
  String get startAsMeterAction => 'Taximeter';

  @override
  String get callConnectingLabel => 'Connecting…';

  @override
  String get callCounterpartyLabel => 'The other side of this call';

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
  String get hangUpCallAction => 'Hang up';

  @override
  String get muteCallAction => 'Mute microphone';

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
  String get driverProfileFamilyNameFieldLabel => 'Family name';

  @override
  String get driverProfileNameFieldLabel => 'Given name';

  @override
  String get driverProfileCarFieldLabel => 'Car model';

  @override
  String get driverProfileColorFieldLabel => 'Color';

  @override
  String get driverProfilePlateFieldLabel => 'License plate';

  @override
  String get driverProfileKmTariffFieldLabel => 'Per-km tariff (₮/km)';

  @override
  String get driverProfileWaitTariffFieldLabel => 'Waiting tariff (₮/min)';

  @override
  String get driverProfileWaitTariffHint =>
      'Per minute stopped in traffic. 0 means free.';

  @override
  String get saveDriverProfileAction => 'Save';

  @override
  String get driverProfileSavedConfirmation => 'Profile saved';

  @override
  String get driverProfileNameSectionTitle => 'Your name';

  @override
  String get driverProfilePhotoSectionTitle => 'Your photo';

  @override
  String get driverProfilePhotoRequiredHint =>
      'A photo where your face is clearly visible is required.';

  @override
  String get driverProfileTakePhotoAction => 'Take a photo';

  @override
  String get driverProfileChoosePhotoAction => 'Choose from gallery';

  @override
  String get driverProfilePhotoCheckingLabel => 'Checking the photo…';

  @override
  String get driverProfilePhotoNotProofDisclaimer =>
      'This photo helps a rider recognise you. It does not prove that you are that person: all the app checks is that a human face is in the picture. Someone else\'s photo, or a photo of a screen, can pass the same check.';

  @override
  String get driverProfilePhotoPermissionDeniedHint =>
      'Permission to use the camera or your photo library was denied. Grant it in your phone settings and try again.';

  @override
  String get driverProfilePhotoPickFailedHint =>
      'Couldn\'t get that photo. Please try again.';

  @override
  String get driverProfilePhotoSaveFailedHint =>
      'Couldn\'t save that photo. Please try again.';

  @override
  String get driverPhotoRejectedUndecodable =>
      'This file couldn\'t be read as an image. Please choose another one.';

  @override
  String get driverPhotoRejectedTooLarge =>
      'That photo is still too large even after shrinking. Please choose a smaller one.';

  @override
  String get driverPhotoRejectedNoFace =>
      'No face found. Hold the phone closer to your face, turn towards the light and try again.';

  @override
  String get driverPhotoRejectedMultipleFaces =>
      'There is more than one person in this photo. Choose one where you are alone.';

  @override
  String get driverPhotoRejectedFaceTooSmall =>
      'Your face is too small in the frame. Take it closer, so your face fills it.';

  @override
  String get driverPhotoRejectedCheckUnavailable =>
      'The photo checker isn\'t working in this build, so no photo can be saved — please update the app.';

  @override
  String get driverNameProblemEmpty => 'This can\'t be left empty.';

  @override
  String get driverNameProblemTooLong => 'That\'s too long. Please shorten it.';

  @override
  String get driverNameProblemDisallowedCharacter =>
      'Only letters, spaces, «-», «\'» and «.» are allowed.';

  @override
  String get driverProfileOfferBlockedNameNotice =>
      'Until your family name and given name are filled in, you can\'t send offers to riders.';

  @override
  String get driverProfileOfferBlockedPhotoNotice =>
      'Until you add your photo, you can\'t send offers to riders.';

  @override
  String get driverProfileOfferBlockedUnsavedNotice =>
      'Your name isn\'t saved yet. Tap Save below to confirm it — until then it won\'t travel with an offer.';

  @override
  String get driverProfileOfferReadyNotice =>
      'All set. You can send offers to riders.';

  @override
  String get driverOfferBlockedNameMessage =>
      'To send an offer, fill in your family name and given name first.';

  @override
  String get driverOfferBlockedPhotoMessage =>
      'To send an offer, add your photo first.';

  @override
  String get driverOfferBlockedOpenProfileAction => 'Profile';

  @override
  String get meteredOfferToggleLabel => 'Metered (my km-tariff)';

  @override
  String get meteredOfferNoTariffHint =>
      'Set your km-tariff in your profile first';

  @override
  String meteredOfferTariffPairLabel(String km, String wait) {
    return '$km ₮/km + $wait ₮/min waiting';
  }

  @override
  String meteredOfferNoWaitTariffLabel(String km) {
    return '$km ₮/km, waiting free';
  }

  @override
  String meteredLiveWaitingLabel(String mnt) {
    return 'Waiting · $mnt ₮';
  }

  @override
  String meteredLiveFareLabel(String mnt) {
    return 'Current fare: $mnt ₮';
  }

  @override
  String get meteredFareConfirmTitle => 'Final trip fare';

  @override
  String meteredFareConfirmWaitingRow(int min) {
    return 'Waiting fare ($min min)';
  }

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
  String get leaveSelectedDriverTitle => 'Cancel the driver you picked?';

  @override
  String get leaveSelectedDriverMessage =>
      'The trip has not started yet. Leaving cancels this choice and tells the driver, so they stop coming for you. Riding means requesting again from the beginning.';

  @override
  String get leaveSeedBackupTitle => 'Did you save your recovery words?';

  @override
  String get leaveSeedBackupMessage =>
      'If you don\'t write these 12 words down now, you can never see them again. Lose your phone and your identity is gone for good.';

  @override
  String get onboardingRoleHint => 'One app — for riders and for drivers.';

  @override
  String get seedBackupSubtitle =>
      'These 12 words are your identity. Write them on paper and keep them where nobody else will find them.';

  @override
  String get seedBackupConfirmLabel => 'I have written the 12 words down';

  @override
  String get restoreSubtitle => 'Enter the 12 words you saved earlier.';

  @override
  String restoreWordCountLabel(int count) {
    return '$count / 12 words';
  }

  @override
  String get settingsSubtitle => 'Profile, contact details and safety.';

  @override
  String get settingsDriverProfileMenuHint =>
      'Name, car and rates — this is how riders see your offers.';

  @override
  String get settingsPhoneShareMenuHint =>
      'The number a driver rings when the internet call will not connect.';

  @override
  String get settingsEmergencyContactMenuLabel => 'Emergency contact';

  @override
  String get settingsEmergencyContactMenuHint =>
      'SOS texts your location to this number.';

  @override
  String get settingsLegalNoticeMenuHint =>
      'What Takhi does not vouch for, and who carries the risk.';

  @override
  String get legalNoticeSubtitle => 'Please read this before using Takhi.';

  @override
  String get phoneShareSubtitle =>
      'If the in-app call will not connect, the driver rings this number instead.';

  @override
  String get phoneShareEnabledToggleHint =>
      'While this is on, the number goes only to the driver you picked, and only for that trip.';

  @override
  String get emergencyContactSubtitle =>
      'SOS prepares a message with your location addressed to this number.';

  @override
  String get driverProfileSubtitle =>
      'This is what a rider sees when your offer arrives.';

  @override
  String get driverProfileVehicleSectionTitle => 'Vehicle';

  @override
  String get driverProfilePriceSectionTitle => 'Rates';

  @override
  String get driverProfileKmTariffHint =>
      'Charged per kilometre when a trip runs on the meter.';

  @override
  String get qrCaptureSubtitle =>
      'When the trip ends, the rider scans this code to pay you.';

  @override
  String get sosSheetTitle => 'Emergency help';

  @override
  String get sosSheetSubtitle =>
      'Takhi never dials for you. It opens your phone\'s dialler or messages app, and you press send yourself.';

  @override
  String get sosDialHint => 'Opens the dialler with the number filled in.';

  @override
  String get sosSmsHint => 'Prepares a message carrying your location.';

  @override
  String get sosCancelAction => 'Dismiss';

  @override
  String get meteredLiveFareTitle => 'Current fare';

  @override
  String get meteredFareConfirmSubtitle =>
      'This is the figure from the driver\'s meter. Confirming publishes the receipt; declining publishes none.';

  @override
  String get rateTripStarsHint => '1 star — poor, 5 stars — excellent';

  @override
  String get rateTripCommentPlaceholder => 'Comment (optional)';

  @override
  String get voiceNotesTitle => 'Voice messages';

  @override
  String voiceNoteDurationLabel(int sec) {
    return '$sec sec';
  }

  @override
  String get offerDialogTitle => 'Bid on this call';

  @override
  String get offerDialogSubtitle =>
      'The rider sees three things: your price, how many minutes away you are, and which car.';

  @override
  String get offerRequestNoteLabel => 'Rider\'s note';

  @override
  String offerRequestOfferedPriceLabel(String price) {
    return 'Rider offers: $price ₮';
  }

  @override
  String get driverAwardedTitle => 'This call is yours';

  @override
  String get driverAwardedSubtitle =>
      'The rider picked your offer. Head for the point below.';

  @override
  String get driverInboxListeningTitle => 'Listening for calls';

  @override
  String get driverInboxListeningSubtitle =>
      'Nearby calls appear on the map. Tap one to send an offer.';

  @override
  String driverInboxNearbyCountLabel(int count) {
    return '$count nearby';
  }
}
