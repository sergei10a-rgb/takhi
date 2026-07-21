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
  /// **'{price}₮ · {eta} мин'**
  String offerSummary(int price, int eta);

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

  /// No description provided for @startAsPassengerAction.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага өгөх'**
  String get startAsPassengerAction;

  /// No description provided for @startAsDriverAction.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага сонсох'**
  String get startAsDriverAction;

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
