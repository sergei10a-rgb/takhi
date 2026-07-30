import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_mn.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('mn'),
  ];

  /// No description provided for @appName.
  ///
  /// In mn, this message translates to:
  /// **'Тахь'**
  String get appName;

  /// No description provided for @passengerMode.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигч'**
  String get passengerMode;

  /// No description provided for @driverMode.
  ///
  /// In mn, this message translates to:
  /// **'Жолооч'**
  String get driverMode;

  /// No description provided for @createIdentity.
  ///
  /// In mn, this message translates to:
  /// **'Шинээр эхлэх'**
  String get createIdentity;

  /// No description provided for @restoreIdentity.
  ///
  /// In mn, this message translates to:
  /// **'Сэргээх'**
  String get restoreIdentity;

  /// No description provided for @seedBackupTitle.
  ///
  /// In mn, this message translates to:
  /// **'Нөөц үгсээ хадгал'**
  String get seedBackupTitle;

  /// No description provided for @seedBackupWarning.
  ///
  /// In mn, this message translates to:
  /// **'Энэ 12 үгийг бичиж хадгал. Утсаа гээвэл зөвхөн эдгээрээр сэргээнэ. Хэнд ч бүү харуул.'**
  String get seedBackupWarning;

  /// No description provided for @iSavedIt.
  ///
  /// In mn, this message translates to:
  /// **'Хадгаллаа'**
  String get iSavedIt;

  /// No description provided for @connecting.
  ///
  /// In mn, this message translates to:
  /// **'Холбогдож байна…'**
  String get connecting;

  /// No description provided for @connected.
  ///
  /// In mn, this message translates to:
  /// **'Холбогдлоо'**
  String get connected;

  /// No description provided for @restoreHint.
  ///
  /// In mn, this message translates to:
  /// **'12 нөөц үгээ хооронд нь зайтай бичнэ үү'**
  String get restoreHint;

  /// No description provided for @restoreError.
  ///
  /// In mn, this message translates to:
  /// **'Нөөц үг буруу байна. Дахин шалгаад оруулна уу.'**
  String get restoreError;

  /// No description provided for @createIdentityError.
  ///
  /// In mn, this message translates to:
  /// **'Шинэ бүртгэл үүсгэж чадсангүй. Дахин оролдоно уу.'**
  String get createIdentityError;

  /// No description provided for @overwriteIdentityTitle.
  ///
  /// In mn, this message translates to:
  /// **'Одоогийн бүртгэлийг дарж бичих үү?'**
  String get overwriteIdentityTitle;

  /// No description provided for @overwriteIdentityMessage.
  ///
  /// In mn, this message translates to:
  /// **'Шинэ бүртгэл үүсгэвэл одоогийн хувийн түлхүүр устаж, орлуулагдана. Хуучин нөөц үгээ хадгалаагүй бол дахин сэргээх боломжгүй болно.'**
  String get overwriteIdentityMessage;

  /// No description provided for @overwriteIdentityCancel.
  ///
  /// In mn, this message translates to:
  /// **'Цуцлах'**
  String get overwriteIdentityCancel;

  /// No description provided for @overwriteIdentityConfirm.
  ///
  /// In mn, this message translates to:
  /// **'Тийм, үргэлжлүүл'**
  String get overwriteIdentityConfirm;

  /// No description provided for @landmarkHint.
  ///
  /// In mn, this message translates to:
  /// **'Тэмдэглэл (жишээ: цагаан хаалга)'**
  String get landmarkHint;

  /// No description provided for @nextStep.
  ///
  /// In mn, this message translates to:
  /// **'Үргэлжлүүл'**
  String get nextStep;

  /// No description provided for @publishRide.
  ///
  /// In mn, this message translates to:
  /// **'Нийтлэх'**
  String get publishRide;

  /// No description provided for @priceLabel.
  ///
  /// In mn, this message translates to:
  /// **'Санал үнэ (₮, заавал биш)'**
  String get priceLabel;

  /// No description provided for @offersWaitingTitle.
  ///
  /// In mn, this message translates to:
  /// **'Ирж буй саналууд'**
  String get offersWaitingTitle;

  /// No description provided for @offerSummary.
  ///
  /// In mn, this message translates to:
  /// **'{price} ₮ · {eta} мин'**
  String offerSummary(String price, int eta);

  /// No description provided for @confirmSelectOfferTitle.
  ///
  /// In mn, this message translates to:
  /// **'Энэ жолоочийг сонгох уу?'**
  String get confirmSelectOfferTitle;

  /// No description provided for @confirmSelectOfferMessage.
  ///
  /// In mn, this message translates to:
  /// **'{vehicle} · {price} ₮ · {eta} мин. Баталвал таны яг байршил — утсаа хуваалцахаар тохируулсан бол дугаар ч мөн — энэ жолоочид илгээгдэнэ. Буцааж татах боломжгүй.'**
  String confirmSelectOfferMessage(String vehicle, String price, int eta);

  /// No description provided for @confirmSelectOfferAction.
  ///
  /// In mn, this message translates to:
  /// **'Тийм, илгээх'**
  String get confirmSelectOfferAction;

  /// No description provided for @sendOfferAction.
  ///
  /// In mn, this message translates to:
  /// **'Санал илгээх'**
  String get sendOfferAction;

  /// No description provided for @offerPriceFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Үнэ (₮)'**
  String get offerPriceFieldLabel;

  /// No description provided for @offerEtaFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Хүрэх хугацаа (мин)'**
  String get offerEtaFieldLabel;

  /// No description provided for @offerVehicleFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Машины мэдээлэл'**
  String get offerVehicleFieldLabel;

  /// No description provided for @driverOnTheWay.
  ///
  /// In mn, this message translates to:
  /// **'{vehicle} ирж байна'**
  String driverOnTheWay(String vehicle);

  /// No description provided for @handoffReceivedTitle.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигчийн яг байршил'**
  String get handoffReceivedTitle;

  /// No description provided for @startTripAction.
  ///
  /// In mn, this message translates to:
  /// **'Аялал руу очих'**
  String get startTripAction;

  /// No description provided for @viewActiveTripAction.
  ///
  /// In mn, this message translates to:
  /// **'Аялал эхлүүлэх'**
  String get viewActiveTripAction;

  /// No description provided for @startAsPassengerAction.
  ///
  /// In mn, this message translates to:
  /// **'Унаа дуудах'**
  String get startAsPassengerAction;

  /// No description provided for @startAsDriverAction.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочоор'**
  String get startAsDriverAction;

  /// The destination row's own prompt, shown in place of an address until the rider picks one. It is the sheet's only question -- it used to be repeated as a display-size headline above the same row.
  ///
  /// In mn, this message translates to:
  /// **'Хаашаа явах вэ?'**
  String get homeSheetTitle;

  /// No description provided for @homeDestinationPlaceholder.
  ///
  /// In mn, this message translates to:
  /// **'Очих газар'**
  String get homeDestinationPlaceholder;

  /// Announced for the home destination field, which opens the passenger flow rather than accepting text in place.
  ///
  /// In mn, this message translates to:
  /// **'Очих газраа оруулж дуудлага өгөх'**
  String get homeDestinationSemanticLabel;

  /// No description provided for @homePickupLabel.
  ///
  /// In mn, this message translates to:
  /// **'Суух хаяг'**
  String get homePickupLabel;

  /// What the pickup row leads with once a GPS fix exists and the rider has not named the point themselves. The Plus Code stays underneath it -- this app derives no place names from a geocoding service (spec §6).
  ///
  /// In mn, this message translates to:
  /// **'Одоогийн байршил'**
  String get homeCurrentLocationValue;

  /// No description provided for @homePickupUnknownValue.
  ///
  /// In mn, this message translates to:
  /// **'Байршил тогтоогоогүй'**
  String get homePickupUnknownValue;

  /// No description provided for @homeLocationDeniedHint.
  ///
  /// In mn, this message translates to:
  /// **'Байршлын зөвшөөрөл өгөөгүй байна'**
  String get homeLocationDeniedHint;

  /// No description provided for @homeLocateAction.
  ///
  /// In mn, this message translates to:
  /// **'Байршлаа тогтоох'**
  String get homeLocateAction;

  /// No description provided for @copyPublicKeyAction.
  ///
  /// In mn, this message translates to:
  /// **'Нийтийн түлхүүрээ хуулах'**
  String get copyPublicKeyAction;

  /// No description provided for @publicKeyCopiedConfirmation.
  ///
  /// In mn, this message translates to:
  /// **'Нийтийн түлхүүр хуулагдлаа'**
  String get publicKeyCopiedConfirmation;

  /// No description provided for @qrNotSetHint.
  ///
  /// In mn, this message translates to:
  /// **'Та банкны QR-аа хараахан оруулаагүй байна'**
  String get qrNotSetHint;

  /// No description provided for @qrCaptureTitle.
  ///
  /// In mn, this message translates to:
  /// **'Банкны QR зураг'**
  String get qrCaptureTitle;

  /// No description provided for @qrCaptureAction.
  ///
  /// In mn, this message translates to:
  /// **'Зураг сонгох'**
  String get qrCaptureAction;

  /// No description provided for @qrSaveAction.
  ///
  /// In mn, this message translates to:
  /// **'Хадгалах'**
  String get qrSaveAction;

  /// No description provided for @qrSavedConfirmation.
  ///
  /// In mn, this message translates to:
  /// **'QR хадгалагдлаа'**
  String get qrSavedConfirmation;

  /// No description provided for @qrSaveError.
  ///
  /// In mn, this message translates to:
  /// **'QR хадгалж чадсангүй. Дахин оролдоно уу.'**
  String get qrSaveError;

  /// No description provided for @payWithQrOrCashHint.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү'**
  String get payWithQrOrCashHint;

  /// No description provided for @tripPhaseEnRouteToPickup.
  ///
  /// In mn, this message translates to:
  /// **'Жолооч ирж байна'**
  String get tripPhaseEnRouteToPickup;

  /// No description provided for @tripPhaseInProgress.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын явцад'**
  String get tripPhaseInProgress;

  /// No description provided for @tripPhaseArrived.
  ///
  /// In mn, this message translates to:
  /// **'Хүрлээ'**
  String get tripPhaseArrived;

  /// No description provided for @markPassengerBoardedAction.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигч сууллаа'**
  String get markPassengerBoardedAction;

  /// No description provided for @endTripAction.
  ///
  /// In mn, this message translates to:
  /// **'Аялал дууслаа'**
  String get endTripAction;

  /// No description provided for @rateTripTitle.
  ///
  /// In mn, this message translates to:
  /// **'Аяллыг үнэлнэ үү'**
  String get rateTripTitle;

  /// No description provided for @submitRatingAction.
  ///
  /// In mn, this message translates to:
  /// **'Илгээх'**
  String get submitRatingAction;

  /// No description provided for @tripReceiptPublished.
  ///
  /// In mn, this message translates to:
  /// **'Баримт нийтлэгдлээ'**
  String get tripReceiptPublished;

  /// No description provided for @agreedPriceLabel.
  ///
  /// In mn, this message translates to:
  /// **'Тохирсон үнэ: {price} ₮'**
  String agreedPriceLabel(String price);

  /// No description provided for @locationPermissionNeededHint.
  ///
  /// In mn, this message translates to:
  /// **'Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай'**
  String get locationPermissionNeededHint;

  /// No description provided for @grantLocationPermissionAction.
  ///
  /// In mn, this message translates to:
  /// **'Зөвшөөрөл өгөх'**
  String get grantLocationPermissionAction;

  /// No description provided for @taximeterTitle.
  ///
  /// In mn, this message translates to:
  /// **'Таксиметр'**
  String get taximeterTitle;

  /// No description provided for @meterReadyTitle.
  ///
  /// In mn, this message translates to:
  /// **'Аялалд бэлэн'**
  String get meterReadyTitle;

  /// No description provided for @startMeterAction.
  ///
  /// In mn, this message translates to:
  /// **'Эхлүүл'**
  String get startMeterAction;

  /// No description provided for @meterDestinationOptionalHint.
  ///
  /// In mn, this message translates to:
  /// **'Очих цэг (сонголттой)'**
  String get meterDestinationOptionalHint;

  /// No description provided for @meterDestinationPlaceholder.
  ///
  /// In mn, this message translates to:
  /// **'Очих газраа сонгох'**
  String get meterDestinationPlaceholder;

  /// No description provided for @meterDestinationDoneAction.
  ///
  /// In mn, this message translates to:
  /// **'Болсон'**
  String get meterDestinationDoneAction;

  /// No description provided for @estimatedFareLabel.
  ///
  /// In mn, this message translates to:
  /// **'≈ {mnt} ₮'**
  String estimatedFareLabel(String mnt);

  /// No description provided for @estimatedFareApproxLabel.
  ///
  /// In mn, this message translates to:
  /// **'ойролцоогоор'**
  String get estimatedFareApproxLabel;

  /// No description provided for @meterFareLabel.
  ///
  /// In mn, this message translates to:
  /// **'{mnt} ₮'**
  String meterFareLabel(String mnt);

  /// No description provided for @meterRunningDistanceLabel.
  ///
  /// In mn, this message translates to:
  /// **'{km} км'**
  String meterRunningDistanceLabel(double km);

  /// No description provided for @meterRunningDurationLabel.
  ///
  /// In mn, this message translates to:
  /// **'{min} мин'**
  String meterRunningDurationLabel(int min);

  /// No description provided for @finishMeterAction.
  ///
  /// In mn, this message translates to:
  /// **'Дуусгах'**
  String get finishMeterAction;

  /// No description provided for @meterSummaryTitle.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын дүн'**
  String get meterSummaryTitle;

  /// Finished step: how the total was arrived at.
  ///
  /// In mn, this message translates to:
  /// **'{km} км × {mnt} ₮/км'**
  String meterFareBreakdownLabel(double km, String mnt);

  /// Breakdown row label for the distance half of a metered fare. Shared by the offline taximeter summary and the §7.2 matched-trip fare confirmation -- one wording for one number.
  ///
  /// In mn, this message translates to:
  /// **'Замын хөлс'**
  String get meterSummaryDistanceFareRow;

  /// No description provided for @meterPaymentTitle.
  ///
  /// In mn, this message translates to:
  /// **'Төлбөр'**
  String get meterPaymentTitle;

  /// No description provided for @downloadTakhiQrLabel.
  ///
  /// In mn, this message translates to:
  /// **'Тахь — эзэнгүй такси'**
  String get downloadTakhiQrLabel;

  /// No description provided for @meterTariffTitle.
  ///
  /// In mn, this message translates to:
  /// **'Км-ийн үнээ тохируул'**
  String get meterTariffTitle;

  /// No description provided for @meterTariffSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Тоолуур явсан зайг энэ үнээр бодно.'**
  String get meterTariffSubtitle;

  /// No description provided for @meterTariffFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'1 км-ийн үнэ (₮)'**
  String get meterTariffFieldLabel;

  /// No description provided for @saveTariffAction.
  ///
  /// In mn, this message translates to:
  /// **'Хадгалах'**
  String get saveTariffAction;

  /// No description provided for @meterTariffInvalidHint.
  ///
  /// In mn, this message translates to:
  /// **'Зөв тоо оруулна уу (жишээ нь 1000)'**
  String get meterTariffInvalidHint;

  /// No description provided for @meterEditTariffAction.
  ///
  /// In mn, this message translates to:
  /// **'Тариф: {mnt} ₮/км — засах'**
  String meterEditTariffAction(String mnt);

  /// No description provided for @meterWaitTariffFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'1 минут хүлээлгийн үнэ (₮)'**
  String get meterWaitTariffFieldLabel;

  /// No description provided for @meterWaitTariffHint.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэлд зогсох үед энэ үнээр бодно. 0 бол хүлээлгэ үнэгүй.'**
  String get meterWaitTariffHint;

  /// No description provided for @meterWaitTariffInvalidHint.
  ///
  /// In mn, this message translates to:
  /// **'Зөв тоо оруулна уу (жишээ нь 300)'**
  String get meterWaitTariffInvalidHint;

  /// No description provided for @meterEditWaitTariffAction.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээлгэ: {mnt} ₮/мин — засах'**
  String meterEditWaitTariffAction(String mnt);

  /// No description provided for @meterEstimateExcludesWaitingHint.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэлд зогсвол хүлээлгийн хөлс дээр нь нэмэгдэнэ — урьдчилсан тооцоонд ороогүй.'**
  String get meterEstimateExcludesWaitingHint;

  /// No description provided for @meterModeMovingLabel.
  ///
  /// In mn, this message translates to:
  /// **'Явж байна'**
  String get meterModeMovingLabel;

  /// No description provided for @meterModeWaitingLabel.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээж байна'**
  String get meterModeWaitingLabel;

  /// No description provided for @meterModePausedLabel.
  ///
  /// In mn, this message translates to:
  /// **'Түр зогссон'**
  String get meterModePausedLabel;

  /// No description provided for @meterWaitingTimeLabel.
  ///
  /// In mn, this message translates to:
  /// **'{min} мин хүлээсэн'**
  String meterWaitingTimeLabel(int min);

  /// No description provided for @meterWaitingFareLabel.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээлгэ {mnt} ₮'**
  String meterWaitingFareLabel(String mnt);

  /// No description provided for @pauseMeterAction.
  ///
  /// In mn, this message translates to:
  /// **'Түр зогсоох'**
  String get pauseMeterAction;

  /// No description provided for @resumeMeterAction.
  ///
  /// In mn, this message translates to:
  /// **'Үргэлжлүүлэх'**
  String get resumeMeterAction;

  /// No description provided for @pauseMeterConfirmTitle.
  ///
  /// In mn, this message translates to:
  /// **'Тоолуурыг түр зогсоох уу?'**
  String get pauseMeterConfirmTitle;

  /// No description provided for @pauseMeterConfirmMessage.
  ///
  /// In mn, this message translates to:
  /// **'Зогсоосон хугацаанд км ч, хүлээлгэ ч бодогдохгүй. «Үргэлжлүүлэх» дарж эргүүлж асаана.'**
  String get pauseMeterConfirmMessage;

  /// No description provided for @meterSummaryWaitingFareRow.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээлгийн хөлс'**
  String get meterSummaryWaitingFareRow;

  /// No description provided for @meterSummaryWaitingDurationRow.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээсэн хугацаа'**
  String get meterSummaryWaitingDurationRow;

  /// No description provided for @meterSummaryTotalRow.
  ///
  /// In mn, this message translates to:
  /// **'Нийт'**
  String get meterSummaryTotalRow;

  /// No description provided for @startAsMeterAction.
  ///
  /// In mn, this message translates to:
  /// **'Таксиметр'**
  String get startAsMeterAction;

  /// No description provided for @callConnectingLabel.
  ///
  /// In mn, this message translates to:
  /// **'Холбогдож байна…'**
  String get callConnectingLabel;

  /// No description provided for @callViaPhoneAction.
  ///
  /// In mn, this message translates to:
  /// **'Утсаар залгах'**
  String get callViaPhoneAction;

  /// No description provided for @callFailedOfferPhoneLabel.
  ///
  /// In mn, this message translates to:
  /// **'Апп доторх дуудлага бүтсэнгүй'**
  String get callFailedOfferPhoneLabel;

  /// No description provided for @callEndedLabel.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага дууслаа'**
  String get callEndedLabel;

  /// No description provided for @incomingCallLabel.
  ///
  /// In mn, this message translates to:
  /// **'Ирж буй дуудлага'**
  String get incomingCallLabel;

  /// No description provided for @acceptCallAction.
  ///
  /// In mn, this message translates to:
  /// **'Хариулах'**
  String get acceptCallAction;

  /// No description provided for @declineCallAction.
  ///
  /// In mn, this message translates to:
  /// **'Татгалзах'**
  String get declineCallAction;

  /// No description provided for @startCallAction.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага хийх'**
  String get startCallAction;

  /// No description provided for @voiceNoteTooLongHint.
  ///
  /// In mn, this message translates to:
  /// **'10 секундээс богино байх ёстой'**
  String get voiceNoteTooLongHint;

  /// No description provided for @holdToRecordVoiceNoteHint.
  ///
  /// In mn, this message translates to:
  /// **'Дараад бариад ярь'**
  String get holdToRecordVoiceNoteHint;

  /// No description provided for @shareTripAction.
  ///
  /// In mn, this message translates to:
  /// **'Аялал хуваалцах'**
  String get shareTripAction;

  /// No description provided for @sosAction.
  ///
  /// In mn, this message translates to:
  /// **'SOS'**
  String get sosAction;

  /// No description provided for @emergencyContactPhoneFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Яаралтай үед холбогдох дугаар'**
  String get emergencyContactPhoneFieldLabel;

  /// No description provided for @saveEmergencyContactAction.
  ///
  /// In mn, this message translates to:
  /// **'Хадгалах'**
  String get saveEmergencyContactAction;

  /// No description provided for @locationUnavailableHint.
  ///
  /// In mn, this message translates to:
  /// **'Байршил тодорхойгүй байна'**
  String get locationUnavailableHint;

  /// No description provided for @sosCallPoliceAction.
  ///
  /// In mn, this message translates to:
  /// **'102 — цагдаа'**
  String get sosCallPoliceAction;

  /// No description provided for @sosCallAmbulanceAction.
  ///
  /// In mn, this message translates to:
  /// **'103 — түргэн тусламж'**
  String get sosCallAmbulanceAction;

  /// No description provided for @sosSendLocationSmsAction.
  ///
  /// In mn, this message translates to:
  /// **'Яаралтай холбоо барих хүнд SMS'**
  String get sosSendLocationSmsAction;

  /// No description provided for @sosNoContactHint.
  ///
  /// In mn, this message translates to:
  /// **'Яаралтай үед холбогдох дугаар хадгалагдаагүй байна'**
  String get sosNoContactHint;

  /// No description provided for @sosAddContactAction.
  ///
  /// In mn, this message translates to:
  /// **'Дугаар нэмэх'**
  String get sosAddContactAction;

  /// No description provided for @settingsAction.
  ///
  /// In mn, this message translates to:
  /// **'Тохиргоо'**
  String get settingsAction;

  /// No description provided for @phoneShareSettingsTitle.
  ///
  /// In mn, this message translates to:
  /// **'Утасны дугаар'**
  String get phoneShareSettingsTitle;

  /// No description provided for @phoneShareOwnPhoneFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Таны утасны дугаар'**
  String get phoneShareOwnPhoneFieldLabel;

  /// No description provided for @phoneShareEnabledToggleLabel.
  ///
  /// In mn, this message translates to:
  /// **'Дугаараа тохирсон хүнд илгээх'**
  String get phoneShareEnabledToggleLabel;

  /// No description provided for @savePhoneShareSettingsAction.
  ///
  /// In mn, this message translates to:
  /// **'Хадгалах'**
  String get savePhoneShareSettingsAction;

  /// No description provided for @voiceNoteReceivedLabel.
  ///
  /// In mn, this message translates to:
  /// **'Дуут зурвас ирлээ'**
  String get voiceNoteReceivedLabel;

  /// No description provided for @playVoiceNoteAction.
  ///
  /// In mn, this message translates to:
  /// **'Тоглуулах'**
  String get playVoiceNoteAction;

  /// No description provided for @settingsTitle.
  ///
  /// In mn, this message translates to:
  /// **'Тохиргоо'**
  String get settingsTitle;

  /// No description provided for @settingsDriverProfileMenuLabel.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн профайл'**
  String get settingsDriverProfileMenuLabel;

  /// No description provided for @settingsPhoneShareMenuLabel.
  ///
  /// In mn, this message translates to:
  /// **'Утасны дугаар'**
  String get settingsPhoneShareMenuLabel;

  /// No description provided for @settingsLegalNoticeMenuLabel.
  ///
  /// In mn, this message translates to:
  /// **'Хууль зүйн сануулга'**
  String get settingsLegalNoticeMenuLabel;

  /// No description provided for @driverProfileTitle.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн профайл'**
  String get driverProfileTitle;

  /// No description provided for @driverProfileNameFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Нэр'**
  String get driverProfileNameFieldLabel;

  /// No description provided for @driverProfileCarFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Машины загвар'**
  String get driverProfileCarFieldLabel;

  /// No description provided for @driverProfileColorFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Өнгө'**
  String get driverProfileColorFieldLabel;

  /// No description provided for @driverProfilePlateFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Улсын дугаар'**
  String get driverProfilePlateFieldLabel;

  /// No description provided for @driverProfileKmTariffFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Км-тариф (₮/км)'**
  String get driverProfileKmTariffFieldLabel;

  /// No description provided for @driverProfileWaitTariffFieldLabel.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээлгийн тариф (₮/мин)'**
  String get driverProfileWaitTariffFieldLabel;

  /// No description provided for @driverProfileWaitTariffHint.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэлд зогсох минут тутамд. 0 бол үнэгүй.'**
  String get driverProfileWaitTariffHint;

  /// No description provided for @saveDriverProfileAction.
  ///
  /// In mn, this message translates to:
  /// **'Хадгалах'**
  String get saveDriverProfileAction;

  /// No description provided for @driverProfileSavedConfirmation.
  ///
  /// In mn, this message translates to:
  /// **'Профайл хадгалагдлаа'**
  String get driverProfileSavedConfirmation;

  /// No description provided for @meteredOfferToggleLabel.
  ///
  /// In mn, this message translates to:
  /// **'Таксиметрээр (миний км-тариф)'**
  String get meteredOfferToggleLabel;

  /// No description provided for @meteredOfferNoTariffHint.
  ///
  /// In mn, this message translates to:
  /// **'Эхлээд профайлдаа км-тарифаа тохируулна уу'**
  String get meteredOfferNoTariffHint;

  /// Both halves of a metered price, shown to the driver before they send the offer and to the passenger before they pick it.
  ///
  /// In mn, this message translates to:
  /// **'{km} ₮/км + {wait} ₮/мин хүлээлгэ'**
  String meteredOfferTariffPairLabel(String km, String wait);

  /// A metered price whose driver set no waiting rate -- stated outright rather than left as an absence the reader has to notice.
  ///
  /// In mn, this message translates to:
  /// **'{km} ₮/км, хүлээлгэ үнэгүй'**
  String meteredOfferNoWaitTariffLabel(String km);

  /// Shown during a metered trip while the waiting meter -- never both meters -- is the one running.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээж байна · {mnt} ₮'**
  String meteredLiveWaitingLabel(String mnt);

  /// No description provided for @meteredLiveFareLabel.
  ///
  /// In mn, this message translates to:
  /// **'Одоогийн дүн: {mnt} ₮'**
  String meteredLiveFareLabel(String mnt);

  /// No description provided for @meteredFareConfirmTitle.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын эцсийн дүн'**
  String get meteredFareConfirmTitle;

  /// Breakdown row for the waiting half of a metered fare, with the time behind it so the figure can be checked.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээлгийн хөлс ({min} мин)'**
  String meteredFareConfirmWaitingRow(int min);

  /// No description provided for @meteredFareConfirmAction.
  ///
  /// In mn, this message translates to:
  /// **'Батлах'**
  String get meteredFareConfirmAction;

  /// No description provided for @meteredFareDeclineAction.
  ///
  /// In mn, this message translates to:
  /// **'Татгалзах'**
  String get meteredFareDeclineAction;

  /// No description provided for @meteredFareDeclinedHint.
  ///
  /// In mn, this message translates to:
  /// **'Та дүнг батлаагүй тул баримт нийтлэгдсэнгүй'**
  String get meteredFareDeclinedHint;

  /// No description provided for @legalNoticeTitle.
  ///
  /// In mn, this message translates to:
  /// **'Хууль зүйн мэдэгдэл'**
  String get legalNoticeTitle;

  /// No description provided for @legalNoticeBody.
  ///
  /// In mn, this message translates to:
  /// **'Тахь бол эзэнгүй P2P платформ. Жолоочийн шалгалт байхгүй. Хэрэглэгч ба жолооч эрсдэлээ өөрсдөө хариуцна.'**
  String get legalNoticeBody;

  /// Steps one screen -- or one wizard step -- backwards.
  ///
  /// In mn, this message translates to:
  /// **'Буцах'**
  String get backAction;

  /// Leaves a finished flow for the home screen.
  ///
  /// In mn, this message translates to:
  /// **'Нүүр хуудас руу'**
  String get backToHomeAction;

  /// Dismisses a dialog without doing anything.
  ///
  /// In mn, this message translates to:
  /// **'Цуцлах'**
  String get cancelAction;

  /// Leave-confirmation dialog: keeps the user on the screen.
  ///
  /// In mn, this message translates to:
  /// **'Үлдэх'**
  String get stayAction;

  /// Leave-confirmation dialog: proceeds with leaving.
  ///
  /// In mn, this message translates to:
  /// **'Гарах'**
  String get leaveAction;

  /// Closes a completed trip and returns to the start.
  ///
  /// In mn, this message translates to:
  /// **'Аяллыг дуусгах'**
  String get finishTripAction;

  /// No description provided for @leaveTripTitle.
  ///
  /// In mn, this message translates to:
  /// **'Аялалаас гарах уу?'**
  String get leaveTripTitle;

  /// No description provided for @leaveTripMessage.
  ///
  /// In mn, this message translates to:
  /// **'Идэвхтэй аялал тасарна: байршил дамжуулах, дуудлага хийх боломж хаагдаж, аялалдаа буцаж орох боломжгүй болно. Нөгөө талд мэдэгдэнэ.'**
  String get leaveTripMessage;

  /// No description provided for @leaveMeterTitle.
  ///
  /// In mn, this message translates to:
  /// **'Тоолуурыг зогсоох уу?'**
  String get leaveMeterTitle;

  /// No description provided for @leaveMeterMessage.
  ///
  /// In mn, this message translates to:
  /// **'Одоо гарвал энэ явалтын км, хугацаа, төлбөрийн дүн хадгалагдалгүй устана. Дүнг журналд бичихийн тулд эхлээд «Дуусгах» дарна уу.'**
  String get leaveMeterMessage;

  /// No description provided for @leaveRideRequestTitle.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлагаа цуцлах уу?'**
  String get leaveRideRequestTitle;

  /// No description provided for @leaveRideRequestMessage.
  ///
  /// In mn, this message translates to:
  /// **'Нийтэлсэн дуудлага цуцлагдаж, ирсэн саналууд алга болно. Дахин дуудахын тулд эхнээс нь эхлэх шаардлагатай.'**
  String get leaveRideRequestMessage;

  /// No description provided for @leaveSelectedDriverTitle.
  ///
  /// In mn, this message translates to:
  /// **'Сонгосон жолоочоо цуцлах уу?'**
  String get leaveSelectedDriverTitle;

  /// No description provided for @leaveSelectedDriverMessage.
  ///
  /// In mn, this message translates to:
  /// **'Аялал хараахан эхлээгүй байна. Гарвал энэ сонголт цуцлагдаж, жолоочид мэдэгдэнэ — тэр таныг хүлээхээ болино. Дахин явахын тулд эхнээс нь дуудлага өгнө.'**
  String get leaveSelectedDriverMessage;

  /// No description provided for @leaveSeedBackupTitle.
  ///
  /// In mn, this message translates to:
  /// **'Нөөц үгсээ хадгалсан уу?'**
  String get leaveSeedBackupTitle;

  /// No description provided for @leaveSeedBackupMessage.
  ///
  /// In mn, this message translates to:
  /// **'Энэ 12 үгийг одоо бичиж авахгүй бол дахин харах боломжгүй. Утсаа гээвэл бүртгэлээ бүрмөсөн алдана.'**
  String get leaveSeedBackupMessage;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'mn'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'mn':
      return AppLocalizationsMn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
