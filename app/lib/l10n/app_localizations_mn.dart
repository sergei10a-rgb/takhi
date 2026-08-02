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
  String get relayOfflineChipLabel => 'Сүлжээнд холбогдоогүй';

  @override
  String get relayStatusTitle => 'Реле холболт';

  @override
  String get relayStatusSubtitle =>
      'Тахь-д сервер байхгүй. Дуудлага, санал, баримт бүхэн эдгээр нийтийн реле дамжин очно.';

  @override
  String relayConnectedCountLabel(int connected, int total) {
    return '$connected / $total реле холбогдсон';
  }

  @override
  String get relayNoneConnectedTitle => 'Ямар ч реле холбогдоогүй';

  @override
  String get relayNoneConnectedMessage =>
      'Одоо дуудлага нийтэлбэл хэн ч харахгүй, санал ч ирэхгүй. Интернэтээ шалгаад дахин холбогдоно уу.';

  @override
  String get relayReconnectAction => 'Дахин холбогдох';

  @override
  String get relayReconnectingLabel => 'Дахин холбогдож байна…';

  @override
  String get relayRowConnectedLabel => 'Холбогдсон';

  @override
  String get relayRowUnreachableLabel => 'Холбогдсонгүй';

  @override
  String get relayPublishOfflineWarning =>
      'Сүлжээнд холбогдоогүй байна. Одоо нийтэлбэл дуудлага хэнд ч очихгүй.';

  @override
  String get relayStatusOpenAction => 'Холболтын байдал';

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
  String get passengerPickupStepTitle => 'Хаанаас явах вэ?';

  @override
  String get passengerPickupStepSubtitle =>
      'Газрын зургийг зөөж, зүүг суух цэг дээрээ тааруул.';

  @override
  String get passengerDestinationStepTitle => 'Хаашаа явах вэ?';

  @override
  String get passengerDestinationStepSubtitle =>
      'Газрын зургийг зөөж, зүүг очих цэг дээрээ тааруул.';

  @override
  String get offersRankedByReputationHint =>
      'Хоёр талдаа баталгаажсан аялалд тулгуурлан эрэмбэлэв';

  @override
  String get offersAllNewHint => 'Бүгд шинэ жолооч — ирсэн дарааллаар';

  @override
  String get offersSortedByPriceHint => 'Хамгийн хямд саналаас нь эрэмбэлэв';

  @override
  String get offersSortedByEtaHint => 'Хамгийн хурдан ирэхээс нь эрэмбэлэв';

  @override
  String get offersSortSemanticsLabel => 'Саналуудыг юугаар эрэмбэлэх';

  @override
  String get offersSortReputationOption => 'Нэр хүнд';

  @override
  String get offersSortPriceOption => 'Хямд';

  @override
  String get offersSortEtaOption => 'Хурдан';

  @override
  String get offersWaitingEmptyTitle => 'Саналуудыг хүлээж байна';

  @override
  String get offersWaitingEmptyHint =>
      'Ойролцоох жолооч нар таны дуудлагыг харж байна. Санал ирмэгц энд гарч ирнэ.';

  @override
  String offerEtaLabel(int eta) {
    return '$eta мин';
  }

  @override
  String get offerTopReputationBadge => 'Хамгийн итгэмжтэй';

  @override
  String driverReputationSummaryLabel(int trips, int people) {
    return '$trips аялал · $people хүн баталсан';
  }

  @override
  String get driverNewLabel => 'Шинэ жолооч';

  @override
  String get driverReputationHeading => 'Нэр хүнд';

  @override
  String get driverReputationTripsRow => 'Баталгаажсан аялал';

  @override
  String get driverReputationPeopleRow => 'Өөр өөр хүн';

  @override
  String driverReputationSinceLine(int year, int month) {
    return '$year оны $month-р сараас хойш хуримтлагдсан';
  }

  @override
  String get driverPairedReceiptExplanation =>
      'Аяллын дараа хоёр тал тус тусдаа баримт гарын үсэглэнэ. Зөвхөн хосоороо таарсан баримт энд тоологдоно — ганц талын үнэлгээ жингүй тул хуурамч сайшаал бичих боломжгүй.';

  @override
  String get driverNewExplanation =>
      'Энэ жолооч Тахь дээр шинэ. Энэ нь муу үнэлгээ биш — хос баримттай аялал нь хараахан үүсээгүй гэсэн үг. Жолооч бүр эндээс эхэлдэг.';

  @override
  String get offerDriverNameUnknown => 'Нэрээ илгээгээгүй жолооч';

  @override
  String get driverPhotoUnverifiedBadge => 'Баталгаажаагүй зураг';

  @override
  String get driverPhotoUnverifiedHint =>
      'Жолоочийн утас энэ зурган дотор хүний царай байгааг л шалгасан. Тэр царай яг энэ жолоочийнх мөн эсэхийг хэн ч шалгаагүй. Суухаасаа өмнө нүүр, улсын дугаарыг өөрөө тулгаж үз.';

  @override
  String get driverPhotoEnlargeSemanticLabel => 'Зургийг бүтэн дэлгэцээр харах';

  @override
  String get driverPhotoMissingLabel => 'Зураг илгээгээгүй';

  @override
  String get driverPhotoCloseAction => 'Хаах';

  @override
  String get offerDriverSelectAction => 'Энэ жолоочийг сонгох';

  @override
  String get passengerDriverOnTheWaySubtitle =>
      'Жолооч замдаа явж байна — доор газрын зураг дээр харна. Ярих бол аялал руу ор.';

  @override
  String get offersWaitingTitle => 'Ирж буй саналууд';

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
  String get driverBankQrLabel => 'Жолоочийн банкны QR';

  @override
  String get payWithQrOptionLabel => 'Жолоочийн QR-ыг уншуулах';

  @override
  String get payWithCashOptionLabel => 'Бэлнээр төлөх';

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
  String get locationPermissionNeededTitle => 'Байршлын зөвшөөрөл хэрэгтэй';

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
    return 'Урьдчилсан $mnt ₮';
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
  String get meterTariffTitle => 'Үнээ тохируул';

  @override
  String get meterTariffSubtitle =>
      'Тоолуур эдгээр үнээр бодно. Аль нэгийг хоосон эсвэл 0 орхивол тэр хөлс бодогдохгүй.';

  @override
  String get meterTariffFieldLabel => '1 км-ийн үнэ (₮)';

  @override
  String get saveTariffAction => 'Хадгалах';

  @override
  String get meterTariffInvalidHint => 'Зөв тоо оруулна уу (жишээ нь 1000)';

  @override
  String get meterWaitTariffFieldLabel => 'Түгжрэл/зогсолт (₮/мин)';

  @override
  String get meterWaitTariffHint =>
      'Түгжрэлд зогсох үед энэ үнээр бодно. 0 бол зогсолт үнэгүй.';

  @override
  String get meterWaitTariffInvalidHint => 'Зөв тоо оруулна уу (жишээ нь 300)';

  @override
  String get meterDurationTariffFieldLabel => 'Аяллын хугацаа (₮/мин)';

  @override
  String get meterDurationTariffHint =>
      'Аялал эхэлснээс дуустал минут тутамд — явж байсан ч, зогссон ч. 0 бол үнэгүй.';

  @override
  String get meterDurationTariffInvalidHint =>
      'Зөв тоо оруулна уу (жишээ нь 100)';

  @override
  String meterDurationFareLabel(String mnt) {
    return 'Хугацаа $mnt ₮';
  }

  @override
  String get meterEstimateExcludesWaitingHint =>
      'Түгжрэлд зогсвол зогсолтын хөлс нэмэгдэнэ — урьдчилсан тооцоонд ороогүй.';

  @override
  String get meterEstimateExcludesDurationHint =>
      'Аяллын хугацааны хөлс дээр нь нэмэгдэнэ — урьдчилсан тооцоонд ороогүй.';

  @override
  String get meterModeMovingLabel => 'Явж байна';

  @override
  String get meterModeWaitingLabel => 'Хүлээж байна';

  @override
  String get meterModePausedLabel => 'Түр зогссон';

  @override
  String meterWaitingTimeLabel(int min) {
    return '$min мин зогссон';
  }

  @override
  String meterWaitingFareLabel(String mnt) {
    return 'Зогсолт $mnt ₮';
  }

  @override
  String get pauseMeterAction => 'Түр зогсоох';

  @override
  String get resumeMeterAction => 'Үргэлжлүүлэх';

  @override
  String get pauseMeterConfirmTitle => 'Тоолуурыг түр зогсоох уу?';

  @override
  String get pauseMeterConfirmMessage =>
      'Түр зогсоосон үед км ч, түгжрэл ч бодогдохгүй. «Үргэлжлүүлэх» дарж эргүүлж асаана.';

  @override
  String get pauseMeterDurationStillChargedNote =>
      'Аяллын хугацааны хөлс үүнд хамаарахгүй — түр зогсоосон ч минут тутам бодогдсоор байна.';

  @override
  String get meterSummaryWaitingFareRow => 'Зогсолтын хөлс';

  @override
  String get meterSummaryWaitingDurationRow => 'Зогсолтын хугацаа';

  @override
  String get meterSummaryDurationFareRow => 'Хугацааны хөлс';

  @override
  String get meterSummaryTotalRow => 'Нийт';

  @override
  String get startAsMeterAction => 'Таксиметр';

  @override
  String get callConnectingLabel => 'Холбогдож байна…';

  @override
  String get callCounterpartyLabel => 'Дуудлагын нөгөө тал';

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
  String get hangUpCallAction => 'Дуудлагыг таслах';

  @override
  String get muteCallAction => 'Микрофоныг хаах';

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
  String get driverProfileFamilyNameFieldLabel => 'Овог';

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
  String get driverProfileWaitTariffFieldLabel =>
      'Түгжрэл/зогсолтын тариф (₮/мин)';

  @override
  String get driverProfileWaitTariffHint =>
      'Түгжрэлд зогсох минут тутамд. 0 бол үнэгүй.';

  @override
  String get driverProfileDurationTariffFieldLabel =>
      'Аяллын хугацааны тариф (₮/мин)';

  @override
  String get driverProfileDurationTariffHint =>
      'Аяллын эхнээс дуустал минут тутамд. 0 бол үнэгүй.';

  @override
  String get saveDriverProfileAction => 'Хадгалах';

  @override
  String driverProfileSaveBlockedHint(String fields) {
    return 'Дутуу байна: $fields. Бөглөмөгц «Хадгалах» идэвхжинэ.';
  }

  @override
  String get driverProfileSavedConfirmation => 'Профайл хадгалагдлаа';

  @override
  String get driverProfileNameSectionTitle => 'Таны нэр';

  @override
  String get driverProfilePhotoSectionTitle => 'Таны зураг';

  @override
  String get driverProfilePhotoRequiredHint =>
      'Царай тань тод харагдсан зураг заавал хэрэгтэй.';

  @override
  String get driverProfileTakePhotoAction => 'Камераар авах';

  @override
  String get driverProfileChoosePhotoAction => 'Галерейгаас сонгох';

  @override
  String get driverProfilePhotoCheckingLabel => 'Зургийг шалгаж байна…';

  @override
  String get driverProfilePhotoNotProofDisclaimer =>
      'Энэ зураг зорчигчид таныг таниход тусална. Гэхдээ апп «энэ яг тэр хүн мөн» гэдгийг батлахгүй: зурган дотор хүний царай байгаа эсэхийг л шалгана. Өөр хүний зураг, дэлгэц дээрээс дахин авсан зураг ч шалгалтыг давж болно.';

  @override
  String get driverProfilePhotoPermissionDeniedHint =>
      'Камер эсвэл зургийн санд хандах зөвшөөрөл өгөгдөөгүй байна. Утасныхаа тохиргооноос зөвшөөрөл өгөөд дахин оролдоно уу.';

  @override
  String get driverProfilePhotoPickFailedHint =>
      'Зургийг авч чадсангүй. Дахин оролдоно уу.';

  @override
  String get driverProfilePhotoSaveFailedHint =>
      'Зургийг хадгалж чадсангүй. Дахин оролдоно уу.';

  @override
  String get driverPhotoRejectedUndecodable =>
      'Энэ файлыг зураг болгож уншиж чадсангүй. Өөр зураг сонгоно уу.';

  @override
  String get driverPhotoRejectedTooLarge =>
      'Зураг жижигрүүлсэн ч хэт том хэвээр байна. Арай жижиг зураг сонгоно уу.';

  @override
  String get driverPhotoRejectedNoFace =>
      'Царай олдсонгүй. Утсаа нүүрэндээ ойртуулж, гэрэлтэй тийш харан дахин оролдоно уу.';

  @override
  String get driverPhotoRejectedMultipleFaces =>
      'Зурган дээр нэгээс олон хүн байна. Ганцаараа байгаа зургаа сонгоно уу.';

  @override
  String get driverPhotoRejectedFaceTooSmall =>
      'Царай хэтэрхий жижиг байна. Нүүр дүүрэн харагдахаар ойроос авна уу.';

  @override
  String get driverPhotoRejectedCheckUnavailable =>
      'Зураг шалгагч энэ хувилбарт ажиллахгүй байна. Тиймээс ямар ч зураг хадгалагдахгүй — програмаа шинэчилнэ үү.';

  @override
  String get driverNameProblemEmpty => 'Заавал бөглөнө.';

  @override
  String get driverNameProblemTooLong => 'Хэтэрхий урт байна. Богиносгоно уу.';

  @override
  String get driverNameProblemDisallowedCharacter =>
      'Зөвхөн үсэг, зай, «-», «.» хэрэглэнэ.';

  @override
  String get driverNameProblemNotCyrillic => 'Нэрээ кирилл үсгээр бичнэ үү.';

  @override
  String get driverProfileOfferBlockedNameNotice =>
      'Овог, нэрээ бөглөтөл та зорчигчид санал илгээх боломжгүй.';

  @override
  String get driverProfileOfferBlockedPhotoNotice =>
      'Зургаа оруултал та зорчигчид санал илгээх боломжгүй.';

  @override
  String get driverProfileOfferBlockedUnsavedNotice =>
      'Нэрээ хадгалаагүй байна. Доорх «Хадгалах» дарж баталгаажуулна уу — үгүй бол санал руу нэр тань орохгүй.';

  @override
  String get driverProfileOfferReadyNotice =>
      'Бэлэн. Та зорчигчдод санал илгээж чадна.';

  @override
  String get driverOfferBlockedNameMessage =>
      'Санал илгээхийн тулд эхлээд овог, нэрээ бөглөнө үү.';

  @override
  String get driverOfferBlockedPhotoMessage =>
      'Санал илгээхийн тулд эхлээд зургаа оруулна уу.';

  @override
  String get driverOfferBlockedOpenProfileAction => 'Профайл';

  @override
  String get meteredOfferToggleLabel => 'Таксиметрээр (миний км-тариф)';

  @override
  String get meteredOfferNoTariffHint =>
      'Эхлээд профайлдаа км-тарифаа тохируулна уу';

  @override
  String meteredOfferTariffPairLabel(String km, String wait) {
    return '$km ₮/км + $wait ₮/мин зогсолт';
  }

  @override
  String meteredOfferNoWaitTariffLabel(String km) {
    return '$km ₮/км, зогсолт үнэгүй';
  }

  @override
  String meteredOfferDurationTariffLabel(String duration) {
    return '$duration ₮/мин хугацаа';
  }

  @override
  String meteredLiveWaitingLabel(String mnt) {
    return 'Зогсож байна · $mnt ₮';
  }

  @override
  String meteredLiveFareLabel(String mnt) {
    return 'Одоогийн дүн: $mnt ₮';
  }

  @override
  String get meteredFareConfirmTitle => 'Аяллын эцсийн дүн';

  @override
  String meteredFareConfirmWaitingRow(int min) {
    return 'Зогсолтын хөлс ($min мин)';
  }

  @override
  String meteredFareConfirmDurationRow(int min) {
    return 'Хугацааны хөлс ($min мин)';
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
  String get cancelRideRequestAction => 'Дуудлагаа цуцлах';

  @override
  String get cancelSelectedDriverAction => 'Сонгосон жолоочоо цуцлах';

  @override
  String get cancelRideRequestConfirmTitle => 'Дуудлагаа цуцлах уу?';

  @override
  String get cancelRideRequestConfirmMessage =>
      'Ирсэн саналууд алга болно. Нийтэлсэн дуудлага реле дээр 4 минут хүртэл харагдсаар байх тул хожуу санал ирсэн хэвээр байж болно.';

  @override
  String get cancelSelectedDriverConfirmTitle => 'Сонгосон жолоочоо цуцлах уу?';

  @override
  String get cancelSelectedDriverConfirmMessage =>
      'Жолоочид цуцлалт илгээгдэж, тэр таныг хүлээхээ болино. Дахин явахын тулд эхнээс нь дуудлага өгнө.';

  @override
  String get cancelRideConfirmAction => 'Тийм, цуцлах';

  @override
  String get keepRideAction => 'Үгүй, үлдээх';

  @override
  String get rideRequestCancelledConfirmation => 'Дуудлага цуцлагдлаа';

  @override
  String get driverRideCancelledTitle => 'Зорчигч дуудлагаа цуцаллаа';

  @override
  String get driverRideCancelledMessage =>
      'Энэ дуудлага руу очих шаардлагагүй боллоо. Дуудлага сонсох горим руу буцлаа.';

  @override
  String get driverRideCancelledDismissAction => 'Ойлголоо';

  @override
  String get leaveSeedBackupTitle => 'Нөөц үгсээ хадгалсан уу?';

  @override
  String get leaveSeedBackupMessage =>
      'Энэ 12 үгийг одоо бичиж авахгүй бол дахин харах боломжгүй. Утсаа гээвэл бүртгэлээ бүрмөсөн алдана.';

  @override
  String get onboardingRoleHint => 'Нэг апп — зорчигчид ч, жолоочид ч.';

  @override
  String get seedBackupSubtitle =>
      'Эдгээр 12 үг бол таны бүртгэл. Цаасан дээр бичиж, өөр хүн олохгүй газар хадгал.';

  @override
  String get seedBackupConfirmLabel => '12 үгээ бичиж авлаа';

  @override
  String get restoreSubtitle => 'Өмнө нь хадгалсан 12 үгээ оруулна уу.';

  @override
  String restoreWordCountLabel(int count) {
    return '$count / 12 үг';
  }

  @override
  String get settingsSubtitle => 'Профайл, холбоо барих, аюулгүй байдал.';

  @override
  String get settingsDriverProfileMenuHint =>
      'Нэр, машин, тариф — зорчигчид саналыг чинь ингэж хардаг.';

  @override
  String get settingsPhoneShareMenuHint =>
      'Интернэт тасарвал жолооч тантай холбогдох дугаар.';

  @override
  String get settingsEmergencyContactMenuLabel => 'Яаралтай үеийн хүн';

  @override
  String get settingsEmergencyContactMenuHint =>
      'SOS дарахад байршлыг чинь энэ дугаар руу SMS-ээр илгээнэ.';

  @override
  String get settingsLegalNoticeMenuHint =>
      'Тахь юуг баталгаажуулдаггүй, эрсдэлийг хэн хариуцах тухай.';

  @override
  String get settingsJournalMenuLabel => 'Аяллын түүх';

  @override
  String get settingsJournalMenuHint =>
      'Таксиметрээр хийсэн аялал, өдөр долоо хоногийн орлого.';

  @override
  String get journalSubtitle => 'Зөвхөн энэ утсанд хадгалагдана.';

  @override
  String get journalTodayRow => 'Өнөөдөр';

  @override
  String get journalWeekRow => 'Энэ 7 хоног';

  @override
  String get journalMonthRow => 'Энэ сар';

  @override
  String journalTripCountLabel(int count) {
    return 'Аялал: $count';
  }

  @override
  String get journalTripsHeading => 'Аяллууд';

  @override
  String journalTripWhenLabel(int month, int day, String time) {
    return '$month-р сарын $day, $time';
  }

  @override
  String get journalEmptyTitle => 'Аялал хараахан алга';

  @override
  String get journalEmptyMessage =>
      'Таксиметрээ ажиллуулаад «Дуусгах» дарах бүрд аялал энд бичигдэнэ. Долоо хоногт хэдэн төгрөг олсноо эндээс харна.';

  @override
  String get journalDeleteAction => 'Устгах';

  @override
  String get journalDeleteConfirmTitle => 'Энэ аяллыг устгах уу?';

  @override
  String get journalDeleteConfirmMessage =>
      'Устгасан аяллыг буцааж сэргээх боломжгүй. Өдөр, долоо хоног, сарын нийлбэрээс ч хасагдана.';

  @override
  String get legalNoticeSubtitle => 'Тахь ашиглахаасаа өмнө уншина уу.';

  @override
  String get phoneShareSubtitle =>
      'Дуудлага холбогдохгүй бол жолооч энэ дугаар руу залгана.';

  @override
  String get phoneShareEnabledToggleHint =>
      'Асаалттай үед дугаар зөвхөн таны сонгосон жолоочид, тэр ч зөвхөн тухайн аялалд очно.';

  @override
  String get emergencyContactSubtitle =>
      'SOS дарахад байршил бүхий мессежийг энэ дугаарт бэлдэнэ.';

  @override
  String get driverProfileSubtitle =>
      'Зорчигч саналыг чинь эдгээрээр нь хардаг.';

  @override
  String get driverProfileVehicleSectionTitle => 'Машин';

  @override
  String get driverProfilePriceSectionTitle => 'Үнэ';

  @override
  String get driverProfileKmTariffHint =>
      'Таксиметрээр явахад 1 км тутамд бодогдоно.';

  @override
  String get qrCaptureSubtitle =>
      'Аялал дуусахад зорчигч энэ QR-ыг уншуулж мөнгө шилжүүлнэ.';

  @override
  String get sosSheetTitle => 'Яаралтай тусламж';

  @override
  String get sosSheetSubtitle =>
      'Тахь өөрөө залгахгүй. Утасны залгагч эсвэл мессеж нээгдэх бөгөөд илгээх товчийг та өөрөө дарна.';

  @override
  String get sosDialHint => 'Утасны залгагч дугаартай нээгдэнэ.';

  @override
  String get sosSmsHint => 'Байршил бүхий мессеж бэлэн болно.';

  @override
  String get sosCancelAction => 'Болих';

  @override
  String get meteredLiveFareTitle => 'Одоогийн дүн';

  @override
  String get meteredFareConfirmSubtitle =>
      'Жолоочийн тоолуурын дүн. Батлавал баримт нийтлэгдэнэ, татгалзвал үгүй.';

  @override
  String get rateTripStarsHint => '1 од — муу, 5 од — маш сайн';

  @override
  String get rateTripCommentPlaceholder => 'Сэтгэгдэл (заавал биш)';

  @override
  String get voiceNotesTitle => 'Дуут зурвас';

  @override
  String voiceNoteDurationLabel(int sec) {
    return '$sec сек';
  }

  @override
  String get offerDialogTitle => 'Дуудлагад санал өгөх';

  @override
  String get offerDialogSubtitle =>
      'Зорчигч гурвыг харна: үнэ, хэдэн минутад ирэх, ямар машин.';

  @override
  String get offerRequestNoteLabel => 'Зорчигчийн тэмдэглэл';

  @override
  String get driverAwardedTitle => 'Дуудлага танийх боллоо';

  @override
  String get driverAwardedSubtitle =>
      'Зорчигч таны саналыг сонголоо. Доорх цэг рүү очно уу.';

  @override
  String get driverInboxListeningTitle => 'Дуудлага сонсож байна';

  @override
  String get driverInboxListeningSubtitle =>
      'Ойролцоох дуудлага газрын зураг дээр гарч ирнэ. Товшоод санал илгээнэ.';

  @override
  String driverInboxNearbyCountLabel(int count) {
    return '$count дуудлага';
  }

  @override
  String routePreviewDistanceLabel(double km) {
    return '$km км';
  }

  @override
  String routePreviewDurationLabel(int minutes) {
    return '$minutes мин орчим';
  }

  @override
  String get routePreviewNoQuoteHint =>
      'Тахь үнэ тогтоодоггүй — зөвхөн зай, хугацааг хэмждэг. Жолооч бүр өөрийн үнээ хэлнэ, та сонгоно.';

  @override
  String get routePreviewOfflineHint =>
      'Интернэт холбогдоогүй тул зам шулуунаар зурагдлаа — жинхэнэ маршрут үүнээс урт болно.';

  @override
  String get passengerReviewStepTitle => 'Аяллаа шалгах';

  @override
  String get passengerReviewStepSubtitle =>
      'Зам, зайгаа хараад нийтэл. Жолооч нар өөрсдөө үнээ хэлнэ.';

  @override
  String get offerTipFieldLabel => 'Нэмэлт мөнгө (₮)';

  @override
  String get offerTipHint => 'Заавал биш. Жолоочийн үнэн дээр нэмнэ.';

  @override
  String offerTipTotalLabel(String total) {
    return 'Нийт: $total ₮';
  }

  @override
  String get offersViewSemanticsLabel => 'Саналуудыг хэрхэн харах';

  @override
  String get offersViewListOption => 'Жагсаалт';

  @override
  String get offersViewMapOption => 'Газрын зураг';

  @override
  String offersQuickPickLabel(String price, int eta) {
    return 'Хамгийн хурдан: $price ₮ · $eta мин';
  }

  @override
  String get passengerAwaitingDriverPositionHint =>
      'Жолоочийн байршлыг хүлээж байна…';

  @override
  String get driverPositionSharedNotice =>
      'Та очих хүртэл зорчигч таны байршлыг газрын зураг дээр харна. Аяллыг цуцалбал зогсоно.';

  @override
  String get locationNoticeChannelName => 'Аяллын байршил';

  @override
  String get meterForegroundNoticeTitle => 'Тахь — тоолуур ажиллаж байна';

  @override
  String get meterForegroundNoticeText =>
      'Аяллын зайг хэмжсээр байна. Дуусгах хүртэл байршил уншигдана.';

  @override
  String get tripForegroundNoticeTitle => 'Тахь — аялал явж байна';

  @override
  String get tripForegroundNoticeText =>
      'Байршлыг аяллын нөгөө талтай хуваалцаж байна.';

  @override
  String get meterRunRestoredNotice =>
      'Дуусаагүй аялал сэргээгдлээ. Апп унтарсан хугацаанд явсан зай тоологдоогүй.';

  @override
  String get meterModeStoppedLabel => 'Зогссон';

  @override
  String get meterStartWaitingAction => 'Хүлээж эхлэх';

  @override
  String get meterStopWaitingAction => 'Хүлээхээ болих';

  @override
  String meterRunningStoppedLabel(int min) {
    return 'Зогссон $min мин';
  }

  @override
  String get meterSummaryBoardingFareRow => 'Суултын хөлс';

  @override
  String get meterSummaryStoppedDurationRow => 'Зогссон хугацаа';

  @override
  String get meterBoardingFieldLabel => 'Суултын хөлс (₮)';

  @override
  String get meterBookingBaseFieldLabel => 'Дуудлагын суурь хөлс (₮)';

  @override
  String get meterDiagnosticsTitle => 'GPS оношилгоо';

  @override
  String get meterDiagnosticsOpenAction => 'GPS оношилгоо';

  @override
  String get meterDiagnosticsExplainer =>
      'Энэ тайлан тоолуур зайг хэрхэн хэмжсэнийг харуулна. Хуваалцвал зөвхөн таны сонгосон хүнд очно — хаашаа ч өөрөө илгээгдэхгүй.';

  @override
  String get meterDiagnosticsShareAction => 'Хуваалцах';

  @override
  String get meterDiagnosticsWriteFailedNotice =>
      'Мөрүүдийг санах ойд бичиж чадсангүй. Дүгнэлт зөв хэвээр, гэхдээ мөр бүрийн бүртгэл дутуу байж болзошгүй.';

  @override
  String get meterChargesTitle => 'Таны хөлс';

  @override
  String get meterChargesEditAction => 'Дүн өөрчлөх';

  @override
  String get meterChargesStartingValuesHint =>
      'Эдгээр нь зөвхөн эхлэх утга. Өөрийнхөө үнийг бич.';

  @override
  String get meterChargeKmLabel => 'Замын хөлс';

  @override
  String get meterChargeWaitLabel => 'Хүлээлгийн хөлс';

  @override
  String get meterChargeDurationLabel => 'Аяллын хугацааны хөлс';

  @override
  String get meterChargeBoardingLabel => 'Суултын хөлс';

  @override
  String get meterChargeBookingBaseLabel => 'Дуудлагын суурь хөлс';

  @override
  String meterChargePerKmValue(String mnt) {
    return '$mnt ₮/км';
  }

  @override
  String meterChargePerMinuteValue(String mnt) {
    return '$mnt ₮/мин';
  }

  @override
  String get meterChargesReviewNotice =>
      'Шинэ хөлс нэмэгдлээ. Бүгдийг нэг хараад, хэрэгтэйг нь өөрчилнө үү.';
}
