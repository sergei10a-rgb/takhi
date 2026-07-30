// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Mongolian (`mn`).
class AppLocalizationsMn extends AppLocalizations {
  AppLocalizationsMn([String locale = 'mn']) : super(locale);

  @override
  String get appName => 'Тахь';

  @override
  String get passengerMode => 'Зорчигч';

  @override
  String get driverMode => 'Жолооч';

  @override
  String get createIdentity => 'Шинээр эхлэх';

  @override
  String get restoreIdentity => 'Сэргээх';

  @override
  String get seedBackupTitle => 'Нөөц үгсээ хадгал';

  @override
  String get seedBackupWarning =>
      'Энэ 12 үгийг бичиж хадгал. Утсаа гээвэл зөвхөн эдгээрээр сэргээнэ. Хэнд ч бүү харуул.';

  @override
  String get iSavedIt => 'Хадгаллаа';

  @override
  String get connecting => 'Холбогдож байна…';

  @override
  String get connected => 'Холбогдлоо';

  @override
  String get restoreHint => '12 нөөц үгээ хооронд нь зайтай бичнэ үү';

  @override
  String get restoreError => 'Нөөц үг буруу байна. Дахин шалгаад оруулна уу.';

  @override
  String get createIdentityError =>
      'Шинэ бүртгэл үүсгэж чадсангүй. Дахин оролдоно уу.';

  @override
  String get overwriteIdentityTitle => 'Одоогийн бүртгэлийг дарж бичих үү?';

  @override
  String get overwriteIdentityMessage =>
      'Шинэ бүртгэл үүсгэвэл одоогийн хувийн түлхүүр устаж, орлуулагдана. Хуучин нөөц үгээ хадгалаагүй бол дахин сэргээх боломжгүй болно.';

  @override
  String get overwriteIdentityCancel => 'Цуцлах';

  @override
  String get overwriteIdentityConfirm => 'Тийм, үргэлжлүүл';

  @override
  String get landmarkHint => 'Тэмдэглэл (жишээ: цагаан хаалга)';

  @override
  String get nextStep => 'Үргэлжлүүл';

  @override
  String get publishRide => 'Нийтлэх';

  @override
  String get priceLabel => 'Санал үнэ (₮, заавал биш)';

  @override
  String get offersWaitingTitle => 'Ирж буй саналууд';

  @override
  String offerSummary(String price, int eta) {
    return '$price ₮ · $eta мин';
  }

  @override
  String get confirmSelectOfferTitle => 'Энэ жолоочийг сонгох уу?';

  @override
  String confirmSelectOfferMessage(String vehicle, String price, int eta) {
    return '$vehicle · $price ₮ · $eta мин. Баталвал таны яг байршил — утсаа хуваалцахаар тохируулсан бол дугаар ч мөн — энэ жолоочид илгээгдэнэ. Буцааж татах боломжгүй.';
  }

  @override
  String get confirmSelectOfferAction => 'Тийм, илгээх';

  @override
  String get sendOfferAction => 'Санал илгээх';

  @override
  String get offerPriceFieldLabel => 'Үнэ (₮)';

  @override
  String get offerEtaFieldLabel => 'Хүрэх хугацаа (мин)';

  @override
  String get offerVehicleFieldLabel => 'Машины мэдээлэл';

  @override
  String driverOnTheWay(String vehicle) {
    return '$vehicle ирж байна';
  }

  @override
  String get handoffReceivedTitle => 'Зорчигчийн яг байршил';

  @override
  String get startTripAction => 'Аялал руу очих';

  @override
  String get viewActiveTripAction => 'Аялал эхлүүлэх';

  @override
  String get startAsPassengerAction => 'Унаа дуудах';

  @override
  String get startAsDriverAction => 'Жолоочоор';

  @override
  String get homeSheetTitle => 'Хаашаа явах вэ?';

  @override
  String get homeDestinationPlaceholder => 'Очих газар';

  @override
  String get homeDestinationSemanticLabel => 'Очих газраа оруулж дуудлага өгөх';

  @override
  String get homePickupLabel => 'Суух хаяг';

  @override
  String get homeCurrentLocationValue => 'Одоогийн байршил';

  @override
  String get homePickupUnknownValue => 'Байршил тогтоогоогүй';

  @override
  String get homeLocationDeniedHint => 'Байршлын зөвшөөрөл өгөөгүй байна';

  @override
  String get homeLocateAction => 'Байршлаа тогтоох';

  @override
  String get copyPublicKeyAction => 'Нийтийн түлхүүрээ хуулах';

  @override
  String get publicKeyCopiedConfirmation => 'Нийтийн түлхүүр хуулагдлаа';

  @override
  String get qrNotSetHint => 'Та банкны QR-аа хараахан оруулаагүй байна';

  @override
  String get qrCaptureTitle => 'Банкны QR зураг';

  @override
  String get qrCaptureAction => 'Зураг сонгох';

  @override
  String get qrSaveAction => 'Хадгалах';

  @override
  String get qrSavedConfirmation => 'QR хадгалагдлаа';

  @override
  String get qrSaveError => 'QR хадгалж чадсангүй. Дахин оролдоно уу.';

  @override
  String get payWithQrOrCashHint =>
      'Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү';

  @override
  String get tripPhaseEnRouteToPickup => 'Жолооч ирж байна';

  @override
  String get tripPhaseInProgress => 'Аяллын явцад';

  @override
  String get tripPhaseArrived => 'Хүрлээ';

  @override
  String get markPassengerBoardedAction => 'Зорчигч сууллаа';

  @override
  String get endTripAction => 'Аялал дууслаа';

  @override
  String get rateTripTitle => 'Аяллыг үнэлнэ үү';

  @override
  String get submitRatingAction => 'Илгээх';

  @override
  String get tripReceiptPublished => 'Баримт нийтлэгдлээ';

  @override
  String agreedPriceLabel(String price) {
    return 'Тохирсон үнэ: $price ₮';
  }

  @override
  String get locationPermissionNeededHint =>
      'Аялал хянахын тулд байршлын зөвшөөрөл шаардлагатай';

  @override
  String get grantLocationPermissionAction => 'Зөвшөөрөл өгөх';

  @override
  String get taximeterTitle => 'Таксиметр';

  @override
  String get meterReadyTitle => 'Аялалд бэлэн';

  @override
  String get startMeterAction => 'Эхлүүл';

  @override
  String get meterDestinationOptionalHint => 'Очих цэг (сонголттой)';

  @override
  String get meterDestinationPlaceholder => 'Очих газраа сонгох';

  @override
  String get meterDestinationDoneAction => 'Болсон';

  @override
  String estimatedFareLabel(String mnt) {
    return '≈ $mnt ₮';
  }

  @override
  String get estimatedFareApproxLabel => 'ойролцоогоор';

  @override
  String meterFareLabel(String mnt) {
    return '$mnt ₮';
  }

  @override
  String meterRunningDistanceLabel(double km) {
    return '$km км';
  }

  @override
  String meterRunningDurationLabel(int min) {
    return '$min мин';
  }

  @override
  String get finishMeterAction => 'Дуусгах';

  @override
  String get meterSummaryTitle => 'Аяллын дүн';

  @override
  String meterFareBreakdownLabel(double km, String mnt) {
    return '$km км × $mnt ₮/км';
  }

  @override
  String get meterSummaryDistanceFareRow => 'Замын хөлс';

  @override
  String get meterPaymentTitle => 'Төлбөр';

  @override
  String get downloadTakhiQrLabel => 'Тахь — эзэнгүй такси';

  @override
  String get meterTariffTitle => 'Км-ийн үнээ тохируул';

  @override
  String get meterTariffSubtitle => 'Тоолуур явсан зайг энэ үнээр бодно.';

  @override
  String get meterTariffFieldLabel => '1 км-ийн үнэ (₮)';

  @override
  String get saveTariffAction => 'Хадгалах';

  @override
  String get meterTariffInvalidHint => 'Зөв тоо оруулна уу (жишээ нь 1000)';

  @override
  String meterEditTariffAction(String mnt) {
    return 'Тариф: $mnt ₮/км — засах';
  }

  @override
  String get meterWaitTariffFieldLabel => '1 минут хүлээлгийн үнэ (₮)';

  @override
  String get meterWaitTariffHint =>
      'Түгжрэлд зогсох үед энэ үнээр бодно. 0 бол хүлээлгэ үнэгүй.';

  @override
  String get meterWaitTariffInvalidHint => 'Зөв тоо оруулна уу (жишээ нь 300)';

  @override
  String meterEditWaitTariffAction(String mnt) {
    return 'Хүлээлгэ: $mnt ₮/мин — засах';
  }

  @override
  String get meterEstimateExcludesWaitingHint =>
      'Түгжрэлд зогсвол хүлээлгийн хөлс дээр нь нэмэгдэнэ — урьдчилсан тооцоонд ороогүй.';

  @override
  String get meterModeMovingLabel => 'Явж байна';

  @override
  String get meterModeWaitingLabel => 'Хүлээж байна';

  @override
  String get meterModePausedLabel => 'Түр зогссон';

  @override
  String meterWaitingTimeLabel(int min) {
    return '$min мин хүлээсэн';
  }

  @override
  String meterWaitingFareLabel(String mnt) {
    return 'Хүлээлгэ $mnt ₮';
  }

  @override
  String get pauseMeterAction => 'Түр зогсоох';

  @override
  String get resumeMeterAction => 'Үргэлжлүүлэх';

  @override
  String get pauseMeterConfirmTitle => 'Тоолуурыг түр зогсоох уу?';

  @override
  String get pauseMeterConfirmMessage =>
      'Зогсоосон хугацаанд км ч, хүлээлгэ ч бодогдохгүй. «Үргэлжлүүлэх» дарж эргүүлж асаана.';

  @override
  String get meterSummaryWaitingFareRow => 'Хүлээлгийн хөлс';

  @override
  String get meterSummaryWaitingDurationRow => 'Хүлээсэн хугацаа';

  @override
  String get meterSummaryTotalRow => 'Нийт';

  @override
  String get startAsMeterAction => 'Таксиметр';

  @override
  String get callConnectingLabel => 'Холбогдож байна…';

  @override
  String get callViaPhoneAction => 'Утсаар залгах';

  @override
  String get callFailedOfferPhoneLabel => 'Апп доторх дуудлага бүтсэнгүй';

  @override
  String get callEndedLabel => 'Дуудлага дууслаа';

  @override
  String get incomingCallLabel => 'Ирж буй дуудлага';

  @override
  String get acceptCallAction => 'Хариулах';

  @override
  String get declineCallAction => 'Татгалзах';

  @override
  String get startCallAction => 'Дуудлага хийх';

  @override
  String get voiceNoteTooLongHint => '10 секундээс богино байх ёстой';

  @override
  String get holdToRecordVoiceNoteHint => 'Дараад бариад ярь';

  @override
  String get shareTripAction => 'Аялал хуваалцах';

  @override
  String get sosAction => 'SOS';

  @override
  String get emergencyContactPhoneFieldLabel => 'Яаралтай үед холбогдох дугаар';

  @override
  String get saveEmergencyContactAction => 'Хадгалах';

  @override
  String get locationUnavailableHint => 'Байршил тодорхойгүй байна';

  @override
  String get sosCallPoliceAction => '102 — цагдаа';

  @override
  String get sosCallAmbulanceAction => '103 — түргэн тусламж';

  @override
  String get sosSendLocationSmsAction => 'Яаралтай холбоо барих хүнд SMS';

  @override
  String get sosNoContactHint =>
      'Яаралтай үед холбогдох дугаар хадгалагдаагүй байна';

  @override
  String get sosAddContactAction => 'Дугаар нэмэх';

  @override
  String get settingsAction => 'Тохиргоо';

  @override
  String get phoneShareSettingsTitle => 'Утасны дугаар';

  @override
  String get phoneShareOwnPhoneFieldLabel => 'Таны утасны дугаар';

  @override
  String get phoneShareEnabledToggleLabel => 'Дугаараа тохирсон хүнд илгээх';

  @override
  String get savePhoneShareSettingsAction => 'Хадгалах';

  @override
  String get voiceNoteReceivedLabel => 'Дуут зурвас ирлээ';

  @override
  String get playVoiceNoteAction => 'Тоглуулах';

  @override
  String get settingsTitle => 'Тохиргоо';

  @override
  String get settingsDriverProfileMenuLabel => 'Жолоочийн профайл';

  @override
  String get settingsPhoneShareMenuLabel => 'Утасны дугаар';

  @override
  String get settingsLegalNoticeMenuLabel => 'Хууль зүйн сануулга';

  @override
  String get driverProfileTitle => 'Жолоочийн профайл';

  @override
  String get driverProfileNameFieldLabel => 'Нэр';

  @override
  String get driverProfileCarFieldLabel => 'Машины загвар';

  @override
  String get driverProfileColorFieldLabel => 'Өнгө';

  @override
  String get driverProfilePlateFieldLabel => 'Улсын дугаар';

  @override
  String get driverProfileKmTariffFieldLabel => 'Км-тариф (₮/км)';

  @override
  String get driverProfileWaitTariffFieldLabel => 'Хүлээлгийн тариф (₮/мин)';

  @override
  String get driverProfileWaitTariffHint =>
      'Түгжрэлд зогсох минут тутамд. 0 бол үнэгүй.';

  @override
  String get saveDriverProfileAction => 'Хадгалах';

  @override
  String get driverProfileSavedConfirmation => 'Профайл хадгалагдлаа';

  @override
  String get meteredOfferToggleLabel => 'Таксиметрээр (миний км-тариф)';

  @override
  String get meteredOfferNoTariffHint =>
      'Эхлээд профайлдаа км-тарифаа тохируулна уу';

  @override
  String meteredOfferTariffPairLabel(String km, String wait) {
    return '$km ₮/км + $wait ₮/мин хүлээлгэ';
  }

  @override
  String meteredOfferNoWaitTariffLabel(String km) {
    return '$km ₮/км, хүлээлгэ үнэгүй';
  }

  @override
  String meteredLiveWaitingLabel(String mnt) {
    return 'Хүлээж байна · $mnt ₮';
  }

  @override
  String meteredLiveFareLabel(String mnt) {
    return 'Одоогийн дүн: $mnt ₮';
  }

  @override
  String get meteredFareConfirmTitle => 'Аяллын эцсийн дүн';

  @override
  String meteredFareConfirmWaitingRow(int min) {
    return 'Хүлээлгийн хөлс ($min мин)';
  }

  @override
  String get meteredFareConfirmAction => 'Батлах';

  @override
  String get meteredFareDeclineAction => 'Татгалзах';

  @override
  String get meteredFareDeclinedHint =>
      'Та дүнг батлаагүй тул баримт нийтлэгдсэнгүй';

  @override
  String get legalNoticeTitle => 'Хууль зүйн мэдэгдэл';

  @override
  String get legalNoticeBody =>
      'Тахь бол эзэнгүй P2P платформ. Жолоочийн шалгалт байхгүй. Хэрэглэгч ба жолооч эрсдэлээ өөрсдөө хариуцна.';

  @override
  String get backAction => 'Буцах';

  @override
  String get backToHomeAction => 'Нүүр хуудас руу';

  @override
  String get cancelAction => 'Цуцлах';

  @override
  String get stayAction => 'Үлдэх';

  @override
  String get leaveAction => 'Гарах';

  @override
  String get finishTripAction => 'Аяллыг дуусгах';

  @override
  String get leaveTripTitle => 'Аялалаас гарах уу?';

  @override
  String get leaveTripMessage =>
      'Идэвхтэй аялал тасарна: байршил дамжуулах, дуудлага хийх боломж хаагдаж, аялалдаа буцаж орох боломжгүй болно. Нөгөө талд мэдэгдэнэ.';

  @override
  String get leaveMeterTitle => 'Тоолуурыг зогсоох уу?';

  @override
  String get leaveMeterMessage =>
      'Одоо гарвал энэ явалтын км, хугацаа, төлбөрийн дүн хадгалагдалгүй устана. Дүнг журналд бичихийн тулд эхлээд «Дуусгах» дарна уу.';

  @override
  String get leaveRideRequestTitle => 'Дуудлагаа цуцлах уу?';

  @override
  String get leaveRideRequestMessage =>
      'Нийтэлсэн дуудлага цуцлагдаж, ирсэн саналууд алга болно. Дахин дуудахын тулд эхнээс нь эхлэх шаардлагатай.';

  @override
  String get leaveSelectedDriverTitle => 'Сонгосон жолоочоо цуцлах уу?';

  @override
  String get leaveSelectedDriverMessage =>
      'Аялал хараахан эхлээгүй байна. Гарвал энэ сонголт цуцлагдаж, жолоочид мэдэгдэнэ — тэр таныг хүлээхээ болино. Дахин явахын тулд эхнээс нь дуудлага өгнө.';

  @override
  String get leaveSeedBackupTitle => 'Нөөц үгсээ хадгалсан уу?';

  @override
  String get leaveSeedBackupMessage =>
      'Энэ 12 үгийг одоо бичиж авахгүй бол дахин харах боломжгүй. Утсаа гээвэл бүртгэлээ бүрмөсөн алдана.';
}
