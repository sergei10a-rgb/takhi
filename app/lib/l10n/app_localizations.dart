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

  /// The home status chip when not one relay holds a socket. Says the state, not a count: «Холбогдлоо (0)» was the old label and it was a lie in the one case that matters.
  ///
  /// In mn, this message translates to:
  /// **'Сүлжээнд холбогдоогүй'**
  String get relayOfflineChipLabel;

  /// No description provided for @relayStatusTitle.
  ///
  /// In mn, this message translates to:
  /// **'Реле холболт'**
  String get relayStatusTitle;

  /// Why a rider should care about a list of relay addresses at all -- there is no company server behind this app, so these are the whole delivery network.
  ///
  /// In mn, this message translates to:
  /// **'Тахь-д сервер байхгүй. Дуудлага, санал, баримт бүхэн эдгээр нийтийн реле дамжин очно.'**
  String get relayStatusSubtitle;

  /// Connected relays out of the configured ones. Both halves are shown because one alone is unreadable: «2» means nothing without knowing there are four.
  ///
  /// In mn, this message translates to:
  /// **'{connected} / {total} реле холбогдсон'**
  String relayConnectedCountLabel(int connected, int total);

  /// No description provided for @relayNoneConnectedTitle.
  ///
  /// In mn, this message translates to:
  /// **'Ямар ч реле холбогдоогүй'**
  String get relayNoneConnectedTitle;

  /// States the consequence in the rider's own terms first (nobody sees the request, no offer can come back) and only then what to do about it.
  ///
  /// In mn, this message translates to:
  /// **'Одоо дуудлага нийтэлбэл хэн ч харахгүй, санал ч ирэхгүй. Интернэтээ шалгаад дахин холбогдоно уу.'**
  String get relayNoneConnectedMessage;

  /// No description provided for @relayReconnectAction.
  ///
  /// In mn, this message translates to:
  /// **'Дахин холбогдох'**
  String get relayReconnectAction;

  /// No description provided for @relayReconnectingLabel.
  ///
  /// In mn, this message translates to:
  /// **'Дахин холбогдож байна…'**
  String get relayReconnectingLabel;

  /// No description provided for @relayRowConnectedLabel.
  ///
  /// In mn, this message translates to:
  /// **'Холбогдсон'**
  String get relayRowConnectedLabel;

  /// No description provided for @relayRowUnreachableLabel.
  ///
  /// In mn, this message translates to:
  /// **'Холбогдсонгүй'**
  String get relayRowUnreachableLabel;

  /// Shown on home, before the rider enters the ride flow, whenever no relay is reachable. The failure it prevents is the app accepting a ride request, mining proof-of-work for it and waiting for offers that can never arrive.
  ///
  /// In mn, this message translates to:
  /// **'Сүлжээнд холбогдоогүй байна. Одоо нийтэлбэл дуудлага хэнд ч очихгүй.'**
  String get relayPublishOfflineWarning;

  /// Accessible name of the tappable relay chip on home; opens the per-relay list.
  ///
  /// In mn, this message translates to:
  /// **'Холболтын байдал'**
  String get relayStatusOpenAction;

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

  /// S5 heading. Until this existed the pickup step and the destination step were the same screen twice over -- same map, same field, same button -- with nothing on either saying which of the two points was being picked.
  ///
  /// In mn, this message translates to:
  /// **'Хаанаас явах вэ?'**
  String get passengerPickupStepTitle;

  /// No description provided for @passengerPickupStepSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Газрын зургийг зөөж, зүүг суух цэг дээрээ тааруул.'**
  String get passengerPickupStepSubtitle;

  /// No description provided for @passengerDestinationStepTitle.
  ///
  /// In mn, this message translates to:
  /// **'Хаашаа явах вэ?'**
  String get passengerDestinationStepTitle;

  /// No description provided for @passengerDestinationStepSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Газрын зургийг зөөж, зүүг очих цэг дээрээ тааруул.'**
  String get passengerDestinationStepSubtitle;

  /// Why the offers sit in this order. rankRideOffers sorts by reputation; a list that reorders itself without saying why reads as random.
  ///
  /// In mn, this message translates to:
  /// **'Хоёр талдаа баталгаажсан аялалд тулгуурлан эрэмбэлэв'**
  String get offersRankedByReputationHint;

  /// Shown instead of the ranking hint while no driver on the list has a single confirmed trip: the order then carries no meaning and must not claim one.
  ///
  /// In mn, this message translates to:
  /// **'Бүгд шинэ жолооч — ирсэн дарааллаар'**
  String get offersAllNewHint;

  /// Subtitle while the rider has switched the list to OfferSort.price. Every sort mode names itself here, so the heading always answers 'why is this one first'.
  ///
  /// In mn, this message translates to:
  /// **'Хамгийн хямд саналаас нь эрэмбэлэв'**
  String get offersSortedByPriceHint;

  /// Subtitle while the rider has switched the list to OfferSort.eta.
  ///
  /// In mn, this message translates to:
  /// **'Хамгийн хурдан ирэхээс нь эрэмбэлэв'**
  String get offersSortedByEtaHint;

  /// Screen-reader label for the whole sort control, read before its three options.
  ///
  /// In mn, this message translates to:
  /// **'Саналуудыг юугаар эрэмбэлэх'**
  String get offersSortSemanticsLabel;

  /// The default sort: OfferSort.reputation. One or two words -- three of these share the width of a phone.
  ///
  /// In mn, this message translates to:
  /// **'Нэр хүнд'**
  String get offersSortReputationOption;

  /// OfferSort.price.
  ///
  /// In mn, this message translates to:
  /// **'Хямд'**
  String get offersSortPriceOption;

  /// OfferSort.eta.
  ///
  /// In mn, this message translates to:
  /// **'Хурдан'**
  String get offersSortEtaOption;

  /// No description provided for @offersWaitingEmptyTitle.
  ///
  /// In mn, this message translates to:
  /// **'Саналуудыг хүлээж байна'**
  String get offersWaitingEmptyTitle;

  /// No description provided for @offersWaitingEmptyHint.
  ///
  /// In mn, this message translates to:
  /// **'Ойролцоох жолооч нар таны дуудлагыг харж байна. Санал ирмэгц энд гарч ирнэ.'**
  String get offersWaitingEmptyHint;

  /// How long this driver says they need to reach the pickup, as a chip beside the fare.
  ///
  /// In mn, this message translates to:
  /// **'{eta} мин'**
  String offerEtaLabel(int eta);

  /// No description provided for @offerTopReputationBadge.
  ///
  /// In mn, this message translates to:
  /// **'Хамгийн итгэмжтэй'**
  String get offerTopReputationBadge;

  /// A driver's reputation in the one form a passenger can act on. The trustWeight the list sorts by is a bare score nobody can read; 'N trips, confirmed by M different people' is what it is computed from (spec §9), and the second half is the half that cannot be inflated by one enthusiastic pubkey.
  ///
  /// In mn, this message translates to:
  /// **'{trips} аялал · {people} хүн баталсан'**
  String driverReputationSummaryLabel(int trips, int people);

  /// A driver with no paired history yet. Named as new rather than as lacking something ('no confirmed trips'): every driver starts here, and a system whose newcomers read as suspects never gets a second driver.
  ///
  /// In mn, this message translates to:
  /// **'Шинэ жолооч'**
  String get driverNewLabel;

  /// Heading of the reputation breakdown on the driver's page.
  ///
  /// In mn, this message translates to:
  /// **'Нэр хүнд'**
  String get driverReputationHeading;

  /// Row label: how many trips both sides signed a receipt for.
  ///
  /// In mn, this message translates to:
  /// **'Баталгаажсан аялал'**
  String get driverReputationTripsRow;

  /// Row label: how many distinct counterparties those trips came from. The number an attacker has to buy an identity for each time.
  ///
  /// In mn, this message translates to:
  /// **'Өөр өөр хүн'**
  String get driverReputationPeopleRow;

  /// How long this history has been building, as a sentence under the two counts rather than as a third numeric row. Numeric month and year rather than a month name: the app bundles no locale month list, same reason as journalTripWhenLabel.
  ///
  /// In mn, this message translates to:
  /// **'{year} оны {month}-р сараас хойш хуримтлагдсан'**
  String driverReputationSinceLine(int year, int month);

  /// The one sentence that says why these numbers mean anything (spec §9). Without it the counts are just numbers a server could have invented, which is exactly what this app does not have.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын дараа хоёр тал тус тусдаа баримт гарын үсэглэнэ. Зөвхөн хосоороо таарсан баримт энд тоологдоно — ганц талын үнэлгээ жингүй тул хуурамч сайшаал бичих боломжгүй.'**
  String get driverPairedReceiptExplanation;

  /// The new driver's side of the same statement. Shown instead of a bare absence so that starting out is not indistinguishable from being distrusted.
  ///
  /// In mn, this message translates to:
  /// **'Энэ жолооч Тахь дээр шинэ. Энэ нь муу үнэлгээ биш — хос баримттай аялал нь хараахан үүсээгүй гэсэн үг. Жолооч бүр эндээс эхэлдэг.'**
  String get driverNewExplanation;

  /// Fills the name slot when an offer carries no driver name -- only possible from a client older than the name field, since OfferService refuses to send one without. Stated outright rather than falling back to the pubkey, because 'this driver's app sent no name' is the fact a passenger can act on; the key itself is still on the driver sheet one tap away.
  ///
  /// In mn, this message translates to:
  /// **'Нэрээ илгээгээгүй жолооч'**
  String get offerDriverNameUnknown;

  /// Rides on every enlarged driver portrait. The check that let the photo be sent only asked whether a human face is in the picture; whose face it is was never established, and no serverless app can establish it.
  ///
  /// In mn, this message translates to:
  /// **'Баталгаажаагүй зураг'**
  String get driverPhotoUnverifiedBadge;

  /// The sentence under the portrait on the driver sheet. Spells out exactly what the face check does and does not prove, and hands the actual verification back to the passenger -- a rider who trusts a verification that does not exist is worse off than one who knows the picture is unverified.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн утас энэ зурган дотор хүний царай байгааг л шалгасан. Тэр царай яг энэ жолоочийнх мөн эсэхийг хэн ч шалгаагүй. Суухаасаа өмнө нүүр, улсын дугаарыг өөрөө тулгаж үз.'**
  String get driverPhotoUnverifiedHint;

  /// Announced for the portrait, which is a button rather than an illustration: tapping it opens the photo full screen, which is the size a face is actually compared at.
  ///
  /// In mn, this message translates to:
  /// **'Зургийг бүтэн дэлгэцээр харах'**
  String get driverPhotoEnlargeSemanticLabel;

  /// Replaces the unverified badge when there is no portrait at all -- an offer from a client older than the photo field, or one whose photo would not decode.
  ///
  /// In mn, this message translates to:
  /// **'Зураг илгээгээгүй'**
  String get driverPhotoMissingLabel;

  /// Leaves the full-screen portrait. A photo viewer that can only be left by a system gesture is one some riders cannot leave at all.
  ///
  /// In mn, this message translates to:
  /// **'Хаах'**
  String get driverPhotoCloseAction;

  /// The driver sheet's own action. Not the same as confirmSelectOfferAction: this one opens the confirmation, that one answers it.
  ///
  /// In mn, this message translates to:
  /// **'Энэ жолоочийг сонгох'**
  String get offerDriverSelectAction;

  /// No description provided for @passengerDriverOnTheWaySubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Жолооч замдаа явж байна — доор газрын зураг дээр харна. Ярих бол аялал руу ор.'**
  String get passengerDriverOnTheWaySubtitle;

  /// No description provided for @offersWaitingTitle.
  ///
  /// In mn, this message translates to:
  /// **'Ирж буй саналууд'**
  String get offersWaitingTitle;

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

  /// Caption under the driver's own bank code. Two codes share the finished-meter screen and only the smaller one -- the app-download invitation -- used to carry a label, so the plate a passenger is meant to scan was the unnamed one.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн банкны QR'**
  String get driverBankQrLabel;

  /// One of the two ways a passenger settles a finished trip, stated as its own row. The passenger has no code of their own to show, so their receipt screen used to end in half a metre of blank paper under the payment heading.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн QR-ыг уншуулах'**
  String get payWithQrOptionLabel;

  /// The other way. Named outright rather than left as the implied alternative -- cash is what most of these trips are actually paid with.
  ///
  /// In mn, this message translates to:
  /// **'Бэлнээр төлөх'**
  String get payWithCashOptionLabel;

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

  /// Heading of the location-denied state, which was a single grey sentence and a gold button floating on an otherwise empty page -- no title, no card, nothing saying which screen the user was still on.
  ///
  /// In mn, this message translates to:
  /// **'Байршлын зөвшөөрөл хэрэгтэй'**
  String get locationPermissionNeededTitle;

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

  /// The pre-trip fare guess, as a chip. The word carries what a ≈ used to: U+2248 is absent from the bundled NotoSans subset, so it rendered as an empty box on the one screen it appeared on -- and a sign nobody can see is worse than the word it stood for.
  ///
  /// In mn, this message translates to:
  /// **'Урьдчилсан {mnt} ₮'**
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

  /// Heading of the taximeter's own tariff form. It used to read «Км-ийн үнээ тохируул», which was already loose when a stopped-time rate joined the km one and became plainly wrong when the trip-duration rate made three -- a driver was told the screen sets the km price while three different prices sat under the heading.
  ///
  /// In mn, this message translates to:
  /// **'Үнээ тохируул'**
  String get meterTariffTitle;

  /// Says what the whole form does now that it holds three independent rates, and states the thing a driver most needs to know about the two they may not want: leaving one blank is a valid answer, not an unfinished form. Every rate is optional by the author's decision; only the km one is required to save a published profile, and that is a different form.
  ///
  /// In mn, this message translates to:
  /// **'Тоолуур эдгээр үнээр бодно. Аль нэгийг хоосон эсвэл 0 орхивол тэр хөлс бодогдохгүй.'**
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

  /// The stopped-time rate on the offline taximeter's tariff form. Renamed 2026-08-01 from «хүлээлгэ» (waiting) to «түгжрэл/зогсолт» (jam/stop) at the author's request: what this rate actually bills is a car standing still in Ulaanbaatar traffic, and «хүлээлгэ» reads to a driver as waiting for a passenger who has not come down yet. The key name is left as it was on purpose -- renaming it would churn every call site for a wording change.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэл/зогсолт (₮/мин)'**
  String get meterWaitTariffFieldLabel;

  /// No description provided for @meterWaitTariffHint.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэлд зогсох үед энэ үнээр бодно. 0 бол зогсолт үнэгүй.'**
  String get meterWaitTariffHint;

  /// No description provided for @meterWaitTariffInvalidHint.
  ///
  /// In mn, this message translates to:
  /// **'Зөв тоо оруулна уу (жишээ нь 300)'**
  String get meterWaitTariffInvalidHint;

  /// Reopens the stopped-time rate for editing, with the rate in force printed on it. The short half of «түгжрэл/зогсолт» because this sits in a row beside the km-tariff's twin: the full wording pushes the number off a 360dp screen.
  ///
  /// In mn, this message translates to:
  /// **'Зогсолт: {mnt} ₮/мин — засах'**
  String meterEditWaitTariffAction(String mnt);

  /// The third rate on the offline taximeter's tariff form (added 2026-08-01): every minute of the trip, moving or stopped. Its own key rather than a reuse of driverProfileDurationTariffFieldLabel because the meter and the published profile are two separate forms that happen to price the same thing -- exactly as meterWaitTariffFieldLabel and driverProfileWaitTariffFieldLabel already are.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын хугацаа (₮/мин)'**
  String get meterDurationTariffFieldLabel;

  /// Spells out the one thing that distinguishes this rate from the stopped-time rate above it: it runs the whole time. It deliberately says nothing about the two overlapping when both are set -- the author decided that is the driver's own commercial call, not something the app warns about.
  ///
  /// In mn, this message translates to:
  /// **'Аялал эхэлснээс дуустал минут тутамд — явж байсан ч, зогссон ч. 0 бол үнэгүй.'**
  String get meterDurationTariffHint;

  /// Its own example figure rather than a reuse of the stopped-time verdict: all three fields can be refused in one pass, and three identical sentences under three boxes leave a driver counting rows to work out which number the app could not read.
  ///
  /// In mn, this message translates to:
  /// **'Зөв тоо оруулна уу (жишээ нь 100)'**
  String get meterDurationTariffInvalidHint;

  /// Reopens the trip-duration rate for editing, with the rate in force printed on it. Only ever rendered when that rate is non-zero, so unlike its two neighbours it never reads «0 ₮/мин».
  ///
  /// In mn, this message translates to:
  /// **'Хугацаа: {mnt} ₮/мин — засах'**
  String meterEditDurationTariffAction(String mnt);

  /// The running meter's live trip-duration charge, and the same figure as a chip on a journal row. Deliberately the same shape as meterWaitingFareLabel: the two sit side by side on the running sheet and must read as two members of one set.
  ///
  /// In mn, this message translates to:
  /// **'Хугацаа {mnt} ₮'**
  String meterDurationFareLabel(String mnt);

  /// No description provided for @meterEstimateExcludesWaitingHint.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэлд зогсвол зогсолтын хөлс нэмэгдэнэ — урьдчилсан тооцоонд ороогүй.'**
  String get meterEstimateExcludesWaitingHint;

  /// The pre-trip estimate is distance only (estimateFareMntOffline). A driver who charges by trip duration would otherwise be quoting a number that is short by the whole time charge, with nothing on screen saying so -- the same honesty the stopped-time caveat beside it exists for.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын хугацааны хөлс дээр нь нэмэгдэнэ — урьдчилсан тооцоонд ороогүй.'**
  String get meterEstimateExcludesDurationHint;

  /// No description provided for @meterModeMovingLabel.
  ///
  /// In mn, this message translates to:
  /// **'Явж байна'**
  String get meterModeMovingLabel;

  /// The running meter's state badge while the car is standing still. Deliberately NOT swept into the 2026-08-01 «хүлээлгэ» -> «түгжрэл/зогсолт» rename, unlike every label that names the charge itself. The obvious rewordings all collide with meterModePausedLabel «Түр зогссон» sitting in the same badge, and these two states differ by exactly the thing that matters: stopped is billing, paused is not. Two near-identical words for those on a glanceable screen in a moving car is a worse defect than the vocabulary split. Left for the author to settle -- it needs a word, not a rename.
  ///
  /// In mn, this message translates to:
  /// **'Хүлээж байна'**
  String get meterModeWaitingLabel;

  /// No description provided for @meterModePausedLabel.
  ///
  /// In mn, this message translates to:
  /// **'Түр зогссон'**
  String get meterModePausedLabel;

  /// How long the run has spent standing still, in the running meter's stat row. Says «зогссон», not «хүлээсэн», completing the 2026-08-01 rename for the one charge: this figure sits inches from «Зогсолт {mnt} ₮» in the same viewport, and two roots for one charge read as a half-finished rename rather than as a distinction. The mode badge above it is deliberately NOT renamed -- see meterModeWaitingLabel.
  ///
  /// In mn, this message translates to:
  /// **'{min} мин зогссон'**
  String meterWaitingTimeLabel(int min);

  /// No description provided for @meterWaitingFareLabel.
  ///
  /// In mn, this message translates to:
  /// **'Зогсолт {mnt} ₮'**
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
  /// **'Түр зогсоосон үед км ч, түгжрэл ч бодогдохгүй. «Үргэлжлүүлэх» дарж эргүүлж асаана.'**
  String get pauseMeterConfirmMessage;

  /// Shown under pauseMeterConfirmMessage, and only when this driver actually set a trip-duration rate. That rate bills every second from the first GPS fix to the last by design (author's ruling, 2026-08-01), so pausing does not stop it -- and the sentence above, which promises km and stopped time both stop, is true but incomplete for such a driver. They pause for fuel believing the meter is off. Suppressed at a zero rate for the same reason meterEstimateExcludesDurationHint is: a warning about a charge that does not exist teaches drivers to skip the warnings that matter.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын хугацааны хөлс үүнд хамаарахгүй — түр зогсоосон ч минут тутам бодогдсоор байна.'**
  String get pauseMeterDurationStillChargedNote;

  /// Breakdown row label for the stopped-time share of a finished metered fare. The short half of «түгжрэл/зогсолт»: this row has a price sitting to the right of it and must not wrap.
  ///
  /// In mn, this message translates to:
  /// **'Зогсолтын хөлс'**
  String get meterSummaryWaitingFareRow;

  /// The time behind the stopped-time charge, in the finished-run summary. Renamed with meterWaitingTimeLabel and for the same reason -- it sat directly under «Зогсолтын хөлс», naming that row's own minutes with a different word than the row itself.
  ///
  /// In mn, this message translates to:
  /// **'Зогсолтын хугацаа'**
  String get meterSummaryWaitingDurationRow;

  /// Breakdown row label for the trip-duration share of a finished metered fare -- the third row, beside the distance and stopped-time ones. Short for the same reason as its neighbours: a price sits to the right of it.
  ///
  /// In mn, this message translates to:
  /// **'Хугацааны хөлс'**
  String get meterSummaryDurationFareRow;

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

  /// The small standing label above the counterparty key on the call screen. The abbreviated npub is the only identity this app has, and the call screen was the one place in a trip that never said who was on the other end.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлагын нөгөө тал'**
  String get callCounterpartyLabel;

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

  /// The red control on the call sheet. Distinct from declineCallAction, which answers a phone that is still ringing -- a screen reader had been announcing the hang-up button with the word for refusing a call that was never accepted.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлагыг таслах'**
  String get hangUpCallAction;

  /// The microphone toggle on a connected call.
  ///
  /// In mn, this message translates to:
  /// **'Микрофоныг хаах'**
  String get muteCallAction;

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

  /// S17. Family name. Together with the given name this is what a passenger says at the car window instead of reading out «npub1qz8…». Neither half is published to a relay -- both travel only inside the encrypted offer.
  ///
  /// In mn, this message translates to:
  /// **'Овог'**
  String get driverProfileFamilyNameFieldLabel;

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

  /// The stopped-time rate in the driver's own profile -- the form where a driver decides what they charge, so the full «түгжрэл/зогсолт» wording is worth the width here even though the meter's own rows shorten it. It carries «тариф» and the meter's twin (meterWaitTariffFieldLabel) does not, for the same reason «Км-тариф (₮/км)» differs from «1 км-ийн үнэ (₮)» one field above: these are two different forms writing to two different stores (DriverProfileStore here, TariffStore there), and for one commit after the 2026-08-01 rename both read character-for-character alike -- which is precisely the signal that tells a driver they have already filled this in, so they set the rate once and the other form silently stayed at zero.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэл/зогсолтын тариф (₮/мин)'**
  String get driverProfileWaitTariffFieldLabel;

  /// No description provided for @driverProfileWaitTariffHint.
  ///
  /// In mn, this message translates to:
  /// **'Түгжрэлд зогсох минут тутамд. 0 бол үнэгүй.'**
  String get driverProfileWaitTariffHint;

  /// The third rate (added 2026-08-01): charged on every minute of the trip, moving or stopped. Its own field beside the other two because it is its own rate -- a driver may set any of the three, all of them, or none. Worded «...ны тариф» so it cannot be confused with the taximeter's own field for the same rate (meterDurationTariffFieldLabel): see driverProfileWaitTariffFieldLabel's note for what happened when the two matched exactly.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын хугацааны тариф (₮/мин)'**
  String get driverProfileDurationTariffFieldLabel;

  /// Says exactly what the rate bills -- start to finish, whether the car is moving or not -- because that is the one thing that distinguishes it from the stopped-time rate above it. It deliberately says nothing about the two overlapping when both are set: the author decided that is the driver's own commercial call, not something the app warns about.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын эхнээс дуустал минут тутамд. 0 бол үнэгүй.'**
  String get driverProfileDurationTariffHint;

  /// No description provided for @saveDriverProfileAction.
  ///
  /// In mn, this message translates to:
  /// **'Хадгалах'**
  String get saveDriverProfileAction;

  /// Sits directly above the «Хадгалах» button while that button is grey, and names the boxes still holding it grey. Written because a driver who filled in their name and photo, tapped a dead button and left lost the whole form -- the button said nothing about why it would not answer. Calm on purpose: nothing is wrong, the form is simply not finished. The field names come through verbatim from the labels standing above the boxes themselves, so the words in this line are the words the driver has to go and look for.
  ///
  /// In mn, this message translates to:
  /// **'Дутуу байна: {fields}. Бөглөмөгц «Хадгалах» идэвхжинэ.'**
  String driverProfileSaveBlockedHint(String fields);

  /// No description provided for @driverProfileSavedConfirmation.
  ///
  /// In mn, this message translates to:
  /// **'Профайл хадгалагдлаа'**
  String get driverProfileSavedConfirmation;

  /// No description provided for @driverProfileNameSectionTitle.
  ///
  /// In mn, this message translates to:
  /// **'Таны нэр'**
  String get driverProfileNameSectionTitle;

  /// No description provided for @driverProfilePhotoSectionTitle.
  ///
  /// In mn, this message translates to:
  /// **'Таны зураг'**
  String get driverProfilePhotoSectionTitle;

  /// S17. Why the portrait block exists, stated as a requirement rather than as an invitation: without a photo this driver cannot send a single offer, so «нэмж болно» would be a lie.
  ///
  /// In mn, this message translates to:
  /// **'Царай тань тод харагдсан зураг заавал хэрэгтэй.'**
  String get driverProfilePhotoRequiredHint;

  /// No description provided for @driverProfileTakePhotoAction.
  ///
  /// In mn, this message translates to:
  /// **'Камераар авах'**
  String get driverProfileTakePhotoAction;

  /// No description provided for @driverProfileChoosePhotoAction.
  ///
  /// In mn, this message translates to:
  /// **'Галерейгаас сонгох'**
  String get driverProfileChoosePhotoAction;

  /// No description provided for @driverProfilePhotoCheckingLabel.
  ///
  /// In mn, this message translates to:
  /// **'Зургийг шалгаж байна…'**
  String get driverProfilePhotoCheckingLabel;

  /// S17. The load-bearing honesty sentence. The face check is a gate, never proof of identity, and no server-less app can make it one. A passenger who believes a verification that does not exist stops applying the judgement that actually protects them, so this must be said in the driver's own view too -- where the promise is being made.
  ///
  /// In mn, this message translates to:
  /// **'Энэ зураг зорчигчид таныг таниход тусална. Гэхдээ апп «энэ яг тэр хүн мөн» гэдгийг батлахгүй: зурган дотор хүний царай байгаа эсэхийг л шалгана. Өөр хүний зураг, дэлгэц дээрээс дахин авсан зураг ч шалгалтыг давж болно.'**
  String get driverProfilePhotoNotProofDisclaimer;

  /// No description provided for @driverProfilePhotoPermissionDeniedHint.
  ///
  /// In mn, this message translates to:
  /// **'Камер эсвэл зургийн санд хандах зөвшөөрөл өгөгдөөгүй байна. Утасныхаа тохиргооноос зөвшөөрөл өгөөд дахин оролдоно уу.'**
  String get driverProfilePhotoPermissionDeniedHint;

  /// No description provided for @driverProfilePhotoPickFailedHint.
  ///
  /// In mn, this message translates to:
  /// **'Зургийг авч чадсангүй. Дахин оролдоно уу.'**
  String get driverProfilePhotoPickFailedHint;

  /// No description provided for @driverProfilePhotoSaveFailedHint.
  ///
  /// In mn, this message translates to:
  /// **'Зургийг хадгалж чадсангүй. Дахин оролдоно уу.'**
  String get driverProfilePhotoSaveFailedHint;

  /// No description provided for @driverPhotoRejectedUndecodable.
  ///
  /// In mn, this message translates to:
  /// **'Энэ файлыг зураг болгож уншиж чадсангүй. Өөр зураг сонгоно уу.'**
  String get driverPhotoRejectedUndecodable;

  /// No description provided for @driverPhotoRejectedTooLarge.
  ///
  /// In mn, this message translates to:
  /// **'Зураг жижигрүүлсэн ч хэт том хэвээр байна. Арай жижиг зураг сонгоно уу.'**
  String get driverPhotoRejectedTooLarge;

  /// S17. Instructions, never an accusation. The commonest cause is not a photograph of a mountain but a real driver standing too far from the camera, backlit, or in a dark courtyard -- so this sentence has to tell them what to do differently.
  ///
  /// In mn, this message translates to:
  /// **'Царай олдсонгүй. Утсаа нүүрэндээ ойртуулж, гэрэлтэй тийш харан дахин оролдоно уу.'**
  String get driverPhotoRejectedNoFace;

  /// No description provided for @driverPhotoRejectedMultipleFaces.
  ///
  /// In mn, this message translates to:
  /// **'Зурган дээр нэгээс олон хүн байна. Ганцаараа байгаа зургаа сонгоно уу.'**
  String get driverPhotoRejectedMultipleFaces;

  /// No description provided for @driverPhotoRejectedFaceTooSmall.
  ///
  /// In mn, this message translates to:
  /// **'Царай хэтэрхий жижиг байна. Нүүр дүүрэн харагдахаар ойроос авна уу.'**
  String get driverPhotoRejectedFaceTooSmall;

  /// S17. Said out loud rather than failing open. A check that waves everything through when its engine is missing is worse than no check, because the promise stays on the screen after the mechanism behind it is gone.
  ///
  /// In mn, this message translates to:
  /// **'Зураг шалгагч энэ хувилбарт ажиллахгүй байна. Тиймээс ямар ч зураг хадгалагдахгүй — програмаа шинэчилнэ үү.'**
  String get driverPhotoRejectedCheckUnavailable;

  /// No description provided for @driverNameProblemEmpty.
  ///
  /// In mn, this message translates to:
  /// **'Заавал бөглөнө.'**
  String get driverNameProblemEmpty;

  /// No description provided for @driverNameProblemTooLong.
  ///
  /// In mn, this message translates to:
  /// **'Хэтэрхий урт байна. Богиносгоно уу.'**
  String get driverNameProblemTooLong;

  /// No description provided for @driverNameProblemDisallowedCharacter.
  ///
  /// In mn, this message translates to:
  /// **'Зөвхөн үсэг, зай, «-», «.» хэрэглэнэ.'**
  String get driverNameProblemDisallowedCharacter;

  /// No description provided for @driverNameProblemNotCyrillic.
  ///
  /// In mn, this message translates to:
  /// **'Нэрээ кирилл үсгээр бичнэ үү.'**
  String get driverNameProblemNotCyrillic;

  /// No description provided for @driverProfileOfferBlockedNameNotice.
  ///
  /// In mn, this message translates to:
  /// **'Овог, нэрээ бөглөтөл та зорчигчид санал илгээх боломжгүй.'**
  String get driverProfileOfferBlockedNameNotice;

  /// No description provided for @driverProfileOfferBlockedPhotoNotice.
  ///
  /// In mn, this message translates to:
  /// **'Зургаа оруултал та зорчигчид санал илгээх боломжгүй.'**
  String get driverProfileOfferBlockedPhotoNotice;

  /// S17. The state a notice built on the text boxes would have got wrong. OfferService.sendOffer reads the SAVED profile, so a name typed but never saved reaches no offer -- yet the driver can see it on screen and would read «fill in your name» as a bug.
  ///
  /// In mn, this message translates to:
  /// **'Нэрээ хадгалаагүй байна. Доорх «Хадгалах» дарж баталгаажуулна уу — үгүй бол санал руу нэр тань орохгүй.'**
  String get driverProfileOfferBlockedUnsavedNotice;

  /// No description provided for @driverProfileOfferReadyNotice.
  ///
  /// In mn, this message translates to:
  /// **'Бэлэн. Та зорчигчдод санал илгээж чадна.'**
  String get driverProfileOfferReadyNotice;

  /// S16. Shown when a driver taps a nearby request but has no usable saved name. The tap used to do nothing at all, which reads as a broken button rather than as a requirement.
  ///
  /// In mn, this message translates to:
  /// **'Санал илгээхийн тулд эхлээд овог, нэрээ бөглөнө үү.'**
  String get driverOfferBlockedNameMessage;

  /// S16. The same refusal as driverOfferBlockedNameMessage for the other half of driverOfferBlock -- a driver whose name is saved but who has no stored portrait.
  ///
  /// In mn, this message translates to:
  /// **'Санал илгээхийн тулд эхлээд зургаа оруулна уу.'**
  String get driverOfferBlockedPhotoMessage;

  /// S16. The way out of both refusals above: opens /settings/driver-profile, the one screen that fixes either half.
  ///
  /// In mn, this message translates to:
  /// **'Профайл'**
  String get driverOfferBlockedOpenProfileAction;

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
  /// **'{km} ₮/км + {wait} ₮/мин зогсолт'**
  String meteredOfferTariffPairLabel(String km, String wait);

  /// A metered price whose driver set no waiting rate -- stated outright rather than left as an absence the reader has to notice.
  ///
  /// In mn, this message translates to:
  /// **'{km} ₮/км, зогсолт үнэгүй'**
  String meteredOfferNoWaitTariffLabel(String km);

  /// The trip-duration rate on a metered offer, as its own short clause beside meteredOfferTariffPairLabel rather than folded into it. Written as a separate chip because the combined three-rate string does not fit an offer card on a 360dp phone and ellipsed away the word «хугацаа» -- the part that says which rate the number belongs to. Overlaps the stopped-time rate on purpose where a driver sets both (author's ruling, 2026-08-01); both are printed because that overlap is what the passenger is accepting when they pick this offer.
  ///
  /// In mn, this message translates to:
  /// **'{duration} ₮/мин хугацаа'**
  String meteredOfferDurationTariffLabel(String duration);

  /// Shown during a metered trip while the stopped-time meter -- never both meters -- is the one running. Says «зогсож», completing the 2026-08-01 rename for every label that names this charge: it carries the charge's own ₮ figure, so wording it with a different root than the fare it states is the split the rename existed to end. Safe here in a way the taximeter's mode badge is not -- this screen has no paused state for a «зогссон» wording to collide with.
  ///
  /// In mn, this message translates to:
  /// **'Зогсож байна · {mnt} ₮'**
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
  /// **'Зогсолтын хөлс ({min} мин)'**
  String meteredFareConfirmWaitingRow(int min);

  /// Breakdown row for the trip-duration share of a matched-trip fare, with the minutes behind it so a passenger can check the figure against a clock rather than take it on trust -- the same reason the stopped-time row carries its own time.
  ///
  /// In mn, this message translates to:
  /// **'Хугацааны хөлс ({min} мин)'**
  String meteredFareConfirmDurationRow(int min);

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

  /// No description provided for @cancelRideRequestAction.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлагаа цуцлах'**
  String get cancelRideRequestAction;

  /// No description provided for @cancelSelectedDriverAction.
  ///
  /// In mn, this message translates to:
  /// **'Сонгосон жолоочоо цуцлах'**
  String get cancelSelectedDriverAction;

  /// No description provided for @cancelRideRequestConfirmTitle.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлагаа цуцлах уу?'**
  String get cancelRideRequestConfirmTitle;

  /// No description provided for @cancelRideRequestConfirmMessage.
  ///
  /// In mn, this message translates to:
  /// **'Ирсэн саналууд алга болно. Нийтэлсэн дуудлага реле дээр 4 минут хүртэл харагдсаар байх тул хожуу санал ирсэн хэвээр байж болно.'**
  String get cancelRideRequestConfirmMessage;

  /// No description provided for @cancelSelectedDriverConfirmTitle.
  ///
  /// In mn, this message translates to:
  /// **'Сонгосон жолоочоо цуцлах уу?'**
  String get cancelSelectedDriverConfirmTitle;

  /// No description provided for @cancelSelectedDriverConfirmMessage.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочид цуцлалт илгээгдэж, тэр таныг хүлээхээ болино. Дахин явахын тулд эхнээс нь дуудлага өгнө.'**
  String get cancelSelectedDriverConfirmMessage;

  /// No description provided for @cancelRideConfirmAction.
  ///
  /// In mn, this message translates to:
  /// **'Тийм, цуцлах'**
  String get cancelRideConfirmAction;

  /// No description provided for @keepRideAction.
  ///
  /// In mn, this message translates to:
  /// **'Үгүй, үлдээх'**
  String get keepRideAction;

  /// No description provided for @rideRequestCancelledConfirmation.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага цуцлагдлаа'**
  String get rideRequestCancelledConfirmation;

  /// No description provided for @driverRideCancelledTitle.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигч дуудлагаа цуцаллаа'**
  String get driverRideCancelledTitle;

  /// No description provided for @driverRideCancelledMessage.
  ///
  /// In mn, this message translates to:
  /// **'Энэ дуудлага руу очих шаардлагагүй боллоо. Дуудлага сонсох горим руу буцлаа.'**
  String get driverRideCancelledMessage;

  /// No description provided for @driverRideCancelledDismissAction.
  ///
  /// In mn, this message translates to:
  /// **'Ойлголоо'**
  String get driverRideCancelledDismissAction;

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

  /// No description provided for @onboardingRoleHint.
  ///
  /// In mn, this message translates to:
  /// **'Нэг апп — зорчигчид ч, жолоочид ч.'**
  String get onboardingRoleHint;

  /// No description provided for @seedBackupSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Эдгээр 12 үг бол таны бүртгэл. Цаасан дээр бичиж, өөр хүн олохгүй газар хадгал.'**
  String get seedBackupSubtitle;

  /// No description provided for @seedBackupConfirmLabel.
  ///
  /// In mn, this message translates to:
  /// **'12 үгээ бичиж авлаа'**
  String get seedBackupConfirmLabel;

  /// No description provided for @restoreSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Өмнө нь хадгалсан 12 үгээ оруулна уу.'**
  String get restoreSubtitle;

  /// No description provided for @restoreWordCountLabel.
  ///
  /// In mn, this message translates to:
  /// **'{count} / 12 үг'**
  String restoreWordCountLabel(int count);

  /// No description provided for @settingsSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Профайл, холбоо барих, аюулгүй байдал.'**
  String get settingsSubtitle;

  /// No description provided for @settingsDriverProfileMenuHint.
  ///
  /// In mn, this message translates to:
  /// **'Нэр, машин, тариф — зорчигчид саналыг чинь ингэж хардаг.'**
  String get settingsDriverProfileMenuHint;

  /// No description provided for @settingsPhoneShareMenuHint.
  ///
  /// In mn, this message translates to:
  /// **'Интернэт тасарвал жолооч тантай холбогдох дугаар.'**
  String get settingsPhoneShareMenuHint;

  /// No description provided for @settingsEmergencyContactMenuLabel.
  ///
  /// In mn, this message translates to:
  /// **'Яаралтай үеийн хүн'**
  String get settingsEmergencyContactMenuLabel;

  /// No description provided for @settingsEmergencyContactMenuHint.
  ///
  /// In mn, this message translates to:
  /// **'SOS дарахад байршлыг чинь энэ дугаар руу SMS-ээр илгээнэ.'**
  String get settingsEmergencyContactMenuHint;

  /// No description provided for @settingsLegalNoticeMenuHint.
  ///
  /// In mn, this message translates to:
  /// **'Тахь юуг баталгаажуулдаггүй, эрсдэлийг хэн хариуцах тухай.'**
  String get settingsLegalNoticeMenuHint;

  /// Settings row leading to the driver's own taximeter journal, and the heading of that screen -- one wording, since the row is the only way in.
  ///
  /// In mn, this message translates to:
  /// **'Аяллын түүх'**
  String get settingsJournalMenuLabel;

  /// No description provided for @settingsJournalMenuHint.
  ///
  /// In mn, this message translates to:
  /// **'Таксиметрээр хийсэн аялал, өдөр долоо хоногийн орлого.'**
  String get settingsJournalMenuHint;

  /// The journal is written locally and never published (spec §7.4): nothing on this screen is signed, so the line says outright where the numbers live.
  ///
  /// In mn, this message translates to:
  /// **'Зөвхөн энэ утсанд хадгалагдана.'**
  String get journalSubtitle;

  /// No description provided for @journalTodayRow.
  ///
  /// In mn, this message translates to:
  /// **'Өнөөдөр'**
  String get journalTodayRow;

  /// No description provided for @journalWeekRow.
  ///
  /// In mn, this message translates to:
  /// **'Энэ 7 хоног'**
  String get journalWeekRow;

  /// No description provided for @journalMonthRow.
  ///
  /// In mn, this message translates to:
  /// **'Энэ сар'**
  String get journalMonthRow;

  /// How many runs a period holds, under that period's takings. Written as a labelled count rather than "{count} аялал" so neither language has to inflect a noun for the number in front of it.
  ///
  /// In mn, this message translates to:
  /// **'Аялал: {count}'**
  String journalTripCountLabel(int count);

  /// No description provided for @journalTripsHeading.
  ///
  /// In mn, this message translates to:
  /// **'Аяллууд'**
  String get journalTripsHeading;

  /// When one journal row's meter was started. Numeric month and day rather than a month name: the app bundles no locale month list, and a driver scanning their own week reads the date as a number anyway.
  ///
  /// In mn, this message translates to:
  /// **'{month}-р сарын {day}, {time}'**
  String journalTripWhenLabel(int month, int day, String time);

  /// No description provided for @journalEmptyTitle.
  ///
  /// In mn, this message translates to:
  /// **'Аялал хараахан алга'**
  String get journalEmptyTitle;

  /// No description provided for @journalEmptyMessage.
  ///
  /// In mn, this message translates to:
  /// **'Таксиметрээ ажиллуулаад «Дуусгах» дарах бүрд аялал энд бичигдэнэ. Долоо хоногт хэдэн төгрөг олсноо эндээс харна.'**
  String get journalEmptyMessage;

  /// No description provided for @journalDeleteAction.
  ///
  /// In mn, this message translates to:
  /// **'Устгах'**
  String get journalDeleteAction;

  /// No description provided for @journalDeleteConfirmTitle.
  ///
  /// In mn, this message translates to:
  /// **'Энэ аяллыг устгах уу?'**
  String get journalDeleteConfirmTitle;

  /// No description provided for @journalDeleteConfirmMessage.
  ///
  /// In mn, this message translates to:
  /// **'Устгасан аяллыг буцааж сэргээх боломжгүй. Өдөр, долоо хоног, сарын нийлбэрээс ч хасагдана.'**
  String get journalDeleteConfirmMessage;

  /// No description provided for @legalNoticeSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Тахь ашиглахаасаа өмнө уншина уу.'**
  String get legalNoticeSubtitle;

  /// No description provided for @phoneShareSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага холбогдохгүй бол жолооч энэ дугаар руу залгана.'**
  String get phoneShareSubtitle;

  /// No description provided for @phoneShareEnabledToggleHint.
  ///
  /// In mn, this message translates to:
  /// **'Асаалттай үед дугаар зөвхөн таны сонгосон жолоочид, тэр ч зөвхөн тухайн аялалд очно.'**
  String get phoneShareEnabledToggleHint;

  /// No description provided for @emergencyContactSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'SOS дарахад байршил бүхий мессежийг энэ дугаарт бэлдэнэ.'**
  String get emergencyContactSubtitle;

  /// No description provided for @driverProfileSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигч саналыг чинь эдгээрээр нь хардаг.'**
  String get driverProfileSubtitle;

  /// No description provided for @driverProfileVehicleSectionTitle.
  ///
  /// In mn, this message translates to:
  /// **'Машин'**
  String get driverProfileVehicleSectionTitle;

  /// No description provided for @driverProfilePriceSectionTitle.
  ///
  /// In mn, this message translates to:
  /// **'Үнэ'**
  String get driverProfilePriceSectionTitle;

  /// No description provided for @driverProfileKmTariffHint.
  ///
  /// In mn, this message translates to:
  /// **'Таксиметрээр явахад 1 км тутамд бодогдоно.'**
  String get driverProfileKmTariffHint;

  /// No description provided for @qrCaptureSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Аялал дуусахад зорчигч энэ QR-ыг уншуулж мөнгө шилжүүлнэ.'**
  String get qrCaptureSubtitle;

  /// No description provided for @sosSheetTitle.
  ///
  /// In mn, this message translates to:
  /// **'Яаралтай тусламж'**
  String get sosSheetTitle;

  /// No description provided for @sosSheetSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Тахь өөрөө залгахгүй. Утасны залгагч эсвэл мессеж нээгдэх бөгөөд илгээх товчийг та өөрөө дарна.'**
  String get sosSheetSubtitle;

  /// No description provided for @sosDialHint.
  ///
  /// In mn, this message translates to:
  /// **'Утасны залгагч дугаартай нээгдэнэ.'**
  String get sosDialHint;

  /// No description provided for @sosSmsHint.
  ///
  /// In mn, this message translates to:
  /// **'Байршил бүхий мессеж бэлэн болно.'**
  String get sosSmsHint;

  /// No description provided for @sosCancelAction.
  ///
  /// In mn, this message translates to:
  /// **'Болих'**
  String get sosCancelAction;

  /// The small label above the running metered fare during a trip. The figure sits underneath it in the numeric face; a screen reader hears the two as one sentence through meteredLiveFareLabel instead.
  ///
  /// In mn, this message translates to:
  /// **'Одоогийн дүн'**
  String get meteredLiveFareTitle;

  /// Says where the figure came from and what each of the two answers does, above the breakdown the passenger is asked to sign.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн тоолуурын дүн. Батлавал баримт нийтлэгдэнэ, татгалзвал үгүй.'**
  String get meteredFareConfirmSubtitle;

  /// Under the rating heading. Without it a row of five empty stars says nothing about which end is good.
  ///
  /// In mn, this message translates to:
  /// **'1 од — муу, 5 од — маш сайн'**
  String get rateTripStarsHint;

  /// Placeholder of the rating comment field, which was previously an empty unlabelled box.
  ///
  /// In mn, this message translates to:
  /// **'Сэтгэгдэл (заавал биш)'**
  String get rateTripCommentPlaceholder;

  /// Heading over the received-voice-note chips on the trip screen. Deliberately not voiceNoteReceivedLabel, which is the transient SnackBar announcing an arrival.
  ///
  /// In mn, this message translates to:
  /// **'Дуут зурвас'**
  String get voiceNotesTitle;

  /// How long one received voice note runs. Replaces a hardcoded English 's' suffix that was concatenated onto the play action.
  ///
  /// In mn, this message translates to:
  /// **'{sec} сек'**
  String voiceNoteDurationLabel(int sec);

  /// Heading of the driver's offer dialog, which previously opened as three unlabelled fields with no statement of what was being answered.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлагад санал өгөх'**
  String get offerDialogTitle;

  /// No description provided for @offerDialogSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигч гурвыг харна: үнэ, хэдэн минутад ирэх, ямар машин.'**
  String get offerDialogSubtitle;

  /// Labels the free text the passenger attached to their public ride request, shown in the offer dialog so the driver knows which call they are bidding on.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигчийн тэмдэглэл'**
  String get offerRequestNoteLabel;

  /// The driver's offer was the one the passenger picked. The screen previously led with the pickup point and never said this.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага танийх боллоо'**
  String get driverAwardedTitle;

  /// No description provided for @driverAwardedSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Зорчигч таны саналыг сонголоо. Доорх цэг рүү очно уу.'**
  String get driverAwardedSubtitle;

  /// The between-trips state of the driver's inbox, which was previously a bare map with nothing on it saying what the screen was doing.
  ///
  /// In mn, this message translates to:
  /// **'Дуудлага сонсож байна'**
  String get driverInboxListeningTitle;

  /// No description provided for @driverInboxListeningSubtitle.
  ///
  /// In mn, this message translates to:
  /// **'Ойролцоох дуудлага газрын зураг дээр гарч ирнэ. Товшоод санал илгээнэ.'**
  String get driverInboxListeningSubtitle;

  /// How many live ride requests this driver can currently see. Zero is an answer -- it tells a driver the app is working and the street is quiet.
  ///
  /// In mn, this message translates to:
  /// **'{count} дуудлага'**
  String driverInboxNearbyCountLabel(int count);

  /// How long the trip about to be published is. Its own key rather than meterRunningDistanceLabel's: that one states how far a car HAS driven, this one how far it is ABOUT to -- one is a measurement, the other a forecast, and the day either wants a qualifier the other must not inherit it.
  ///
  /// In mn, this message translates to:
  /// **'{km} км'**
  String routePreviewDistanceLabel(double km);

  /// How long the routing service says the drive takes. Hedged in a WORD rather than with a ≈ sign, which the bundled NotoSans subset has no glyph for (font_coverage_test) -- and appears only when a routing service actually returned a duration; it is never derived from the distance.
  ///
  /// In mn, this message translates to:
  /// **'{minutes} мин орчим'**
  String routePreviewDurationLabel(int minutes);

  /// Replaces the old reference-rate hint, which explained an invented ₮/km figure that no longer exists. Says the two things a rider needs on the screen where they type a price: the app measures the trip but does not price it, and the prices come from drivers.
  ///
  /// In mn, this message translates to:
  /// **'Тахь үнэ тогтоодоггүй — зөвхөн зай, хугацааг хэмждэг. Жолооч бүр өөрийн үнээ хэлнэ, та сонгоно.'**
  String get routePreviewNoQuoteHint;

  /// Shown when the routing service could not be reached and the map is drawing the straight line between the two points instead of a road. Names both facts a rider needs: why the line looks like that, and which way the real number will move.
  ///
  /// In mn, this message translates to:
  /// **'Интернэт холбогдоогүй тул зам шулуунаар зурагдлаа — жинхэнэ маршрут үүнээс урт болно.'**
  String get routePreviewOfflineHint;

  /// S7 heading. This step used to ask the passenger to name a price; that box is gone -- the request carries no price at all now -- so the step is what it always also was: the last look at the route before it goes out to every driver nearby.
  ///
  /// In mn, this message translates to:
  /// **'Аяллаа шалгах'**
  String get passengerReviewStepTitle;

  /// Says who prices the trip, because the passenger has just lost the box where they used to. Without this line the step reads as though the app forgot to ask.
  ///
  /// In mn, this message translates to:
  /// **'Зам, зайгаа хараад нийтэл. Жолооч нар өөрсдөө үнээ хэлнэ.'**
  String get passengerReviewStepSubtitle;

  /// Optional bonus on the confirm-offer dialog, added to the price this driver quoted.
  ///
  /// In mn, this message translates to:
  /// **'Нэмэлт мөнгө (₮)'**
  String get offerTipFieldLabel;

  /// States that it is optional and that it ADDS. A passenger who read it as "the price" would type the whole fare again and agree to pay nearly double.
  ///
  /// In mn, this message translates to:
  /// **'Заавал биш. Жолоочийн үнэн дээр нэмнэ.'**
  String get offerTipHint;

  /// Driver price plus bonus, restated so the passenger confirms against the number they will actually hand over.
  ///
  /// In mn, this message translates to:
  /// **'Нийт: {total} ₮'**
  String offerTipTotalLabel(String total);

  /// Screen-reader label for the list/map switch on the offers step, read before its two options.
  ///
  /// In mn, this message translates to:
  /// **'Саналуудыг хэрхэн харах'**
  String get offersViewSemanticsLabel;

  /// The default view: offer rows carrying price, reputation and ETA. One or two words -- it shares a row with the map option.
  ///
  /// In mn, this message translates to:
  /// **'Жагсаалт'**
  String get offersViewListOption;

  /// The map view: a car per offering driver, so the rider can see who is actually near them.
  ///
  /// In mn, this message translates to:
  /// **'Газрын зураг'**
  String get offersViewMapOption;

  /// The hurry-up shortcut on the offers step, naming the offer it will take. The figures are ON the button on purpose: a shortcut that hides what it accepts is one nobody should take, and a rider in a hurry is the least able to check afterwards. "Soonest", not "nearest" -- a car three streets away behind a jam is closer and slower, and arrival time is the question being asked.
  ///
  /// In mn, this message translates to:
  /// **'Хамгийн хурдан: {price} ₮ · {eta} мин'**
  String offersQuickPickLabel(String price, int eta);

  /// Shown under the approach map while the chosen driver has sent no position yet. Said out loud rather than leaving an empty map, which a waiting passenger reads as "the driver is not moving" when in fact their phone may still be waking its GPS.
  ///
  /// In mn, this message translates to:
  /// **'Жолоочийн байршлыг хүлээж байна…'**
  String get passengerAwaitingDriverPositionHint;

  /// Shown to the driver the moment they are awarded a job, because that is the moment their position starts being published to the passenger. Broadcasting somebody position without telling them is not made acceptable by their having agreed to drive somewhere; and a driver who does not want to be watched can only decline if they know.
  ///
  /// In mn, this message translates to:
  /// **'Та очих хүртэл зорчигч таны байршлыг газрын зураг дээр харна. Аяллыг цуцалбал зогсоно.'**
  String get driverPositionSharedNotice;
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
