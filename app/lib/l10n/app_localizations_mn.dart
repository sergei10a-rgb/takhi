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
  String offerSummary(int price, int eta) {
    return '$price₮ · $eta мин';
  }

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
  String get startAsPassengerAction => 'Дуудлага өгөх';

  @override
  String get startAsDriverAction => 'Дуудлага сонсох';

  @override
  String get qrNotSetHint => 'Та банкны QR-аа хараахан оруулаагүй байна';

  @override
  String get qrCaptureTitle => 'Банкны QR зураг';

  @override
  String get qrCaptureAction => 'Зураг сонгох';

  @override
  String get qrSavedConfirmation => 'QR хадгалагдлаа';

  @override
  String get payWithQrOrCashHint =>
      'Жолоочийн QR-ыг уншуулах эсвэл бэлнээр төлнө үү';
}
