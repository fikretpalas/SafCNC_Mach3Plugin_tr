{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uMesajlar.pas - kullanıcıya gösterilen metinler
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  Kullanıcıya gösterilen tüm metinler, çevirisi kolay olsun diye bu
  birimde toplanmıştır.
}
unit uMesajlar;

{$mode objfpc}{$H+}
{$codepage utf8}

interface

const
  EklentiAdi: UnicodeString = 'SafCNC';
  AnaMenuAdi: UnicodeString = 'SafCNC';
  MenuAdi: UnicodeString = 'SafCNC';
  KartPencereBasligi: UnicodeString = 'SafCNC';

  MsjKartAraniyor: UnicodeString = 'SafCNC kartı aranıyor...';
  MsjYeniBaglanti: UnicodeString = 'Yeni USB aygıtı bulundu - SafCNC kartı olup olmadığına bakılıyor...';
  MsjKartBaglandi: UnicodeString = 'SafCNC kartı bağlandı.';
  MsjKartBulunamadi: UnicodeString = 'SafCNC kartı bulunamadı - USB kablosunu ve portu kontrol edin';
  MsjBaglantiKoptu: UnicodeString = 'SafCNC kartı ile bağlantı koptu';
  MsjTersTuslar: UnicodeString = 'Ters yönlü jog tuşlarına basıldı - hareket durdu. Tüm jog tuşlarını bırakın.';
  MsjPencereJogDurdu: UnicodeString = 'Jog durdu - tuşları bırakın';
  MsjTasimadaTus: UnicodeString = 'Taşıma iptal - tuşları bırakın';
  MsjKartBagliDegil: UnicodeString = 'SafCNC kartı bağlı değil - hareket kapalı';
  MsjKartYokSifirlama: UnicodeString = 'SafCNC kartı bağlı değil - Mach3 sıfırlamaya alındı';
  MsjSifirlamadaJogYok: UnicodeString = 'Acil stop durumunda jog yapılamaz';
  MsjProbEtkinDegil: UnicodeString = 'Prob istendi ama prob etkin değil';
  MsjSifirlamadaProbYok: UnicodeString = 'Acil stop durumunda prob yapılamaz';
  MsjProbBekle: UnicodeString = 'Devam eden işlemin bitmesi bekleniyor...';
  MsjLimitAtlamaBitti: UnicodeString = 'Limit atlama modundan çıkıldı';
  MsjKartSifirladi: UnicodeString = 'Kart sıfırlama istedi';
  MsjKartaSifirlama: UnicodeString = 'Karta sıfırlama gönderildi';
  MsjKonumBelirsiz: UnicodeString = 'Kart durma konumunu bildiremedi - eksen konumları hatalı olabilir. Lütfen makineyi referansa gönderin.';
  MsjBilinmeyenHata: UnicodeString = 'bilinmeyen hata kodu %d';
  MsjKartHizi: UnicodeString = 'SafCNC kart hız sınırı: eksen başına %s kHz (5 ms''de %d adım)';
  MsjHizlarYuksek: UnicodeString = 'Eksen hızları kartın sınırını aşıyor - kart bağlanmadı. Motor Tuning''de hızları düşürün.';
  MsjJogBitmedenHareket: UnicodeString = 'Jog durmadan hareket komutu geldi - komut iptal edildi. Makine durunca tekrar deneyin.';

  MsjHata: array[0..13] of UnicodeString = (
    'açılış / normal sıfırlama',
    'acil stop',
    'paket sayacı hatası',
    'sağlama toplamı hatası',
    'bilinmeyen komut',
    'eksik paket',
    'haberleşme zaman aşımı (200 ms)',
    'kart tamponu taştı',
    'adım sınırı aşıldı',
    'karttaki acil stop girişi aktif',
    'bu durumda komuta izin verilmiyor',
    'limit anahtarı tetiklendi',
    'prob teması algılandı',
    'tampon boşaldı - hareket verisi geç geldi');

  HataVeriYapisi: UnicodeString = 'beklenmeyen Mach3 veri yapısı (DLL 32 bit / x86 olarak derlenmelidir).'#13#10 +
    'Eklenti devre dışı bırakıldı.';
  HataDurumPenceresi: UnicodeString = 'Durum penceresi hatası: ';

  PencereKartDurumu: UnicodeString = 'SafCNC kart durumu';
  PencereBagli: UnicodeString = 'Bağlı';
  PencereUsbHazir: UnicodeString = 'Kart hazır - Mach3 sıfırlamada';
  PencereKartYok: UnicodeString = 'Kart bulunamadı';
  PencerePortBicimi: UnicodeString = 'Port: %s, %d baud';

  HizUyarisiBasligi: UnicodeString = 'SafCNC - eksen hızları';
  HizUyarisiPanel: UnicodeString = 'Mach3 eksen hızları kartın sınırını aşıyor';
  HizUyarisiGiris: UnicodeString = 'Kart eksen başına en fazla %s kHz adım hızı verebilir (5 ms''de %d adım).';
  HizUyarisiSatir: UnicodeString = '%s ekseni:  %s birim/dk (%s kHz)  -  en fazla %s birim/dk';
  HizUyarisiSon: UnicodeString = 'Kart bu hızlarla bağlanmaz. Config > Motor Tuning''de hızları düşürüp kaydedin, sonra Reset''e basın.';
  HizDugmeTamam: UnicodeString = 'Tamam';

  { Seri bağlantı hata metinleri (yalnızca iç kullanım / hata ayıklama) }
  SerPortAcilamadi: UnicodeString = 'port açılamadı: ';
  SerGetCommState: UnicodeString = 'GetCommState başarısız: ';
  SerSetCommState: UnicodeString = 'SetCommState başarısız: ';
  SerVeriYok: UnicodeString = 'karttan veri gelmiyor (zaman aşımı)';
  SerKartYanitYok: UnicodeString = 'bu portta kart yanıt vermiyor: ';
  SerPortYok: UnicodeString = 'seri port yok';
  SerOkumaHatasi: UnicodeString = 'okuma hatası ';
  SerOkumaBeklemeHatasi: UnicodeString = 'okuma bekleme hatası ';
  SerYazmaHatasi: UnicodeString = 'yazma hatası ';
  SerYazmaZamanAsimi: UnicodeString = 'yazma zaman aşımı (port veri kabul etmiyor)';

{ bicim içindeki %s / %d yer tutucularını sırayla degerler ile değiştirir. }
function Bicimle(const bicim: UnicodeString; const degerler: array of UnicodeString): UnicodeString;

{ Kartın sıfırlama kodu (H) için mesaj. }
function KartSifirlamaMesaji(h: Byte; karttan: Boolean): UnicodeString;

implementation

uses
  SysUtils;

function Bicimle(const bicim: UnicodeString; const degerler: array of UnicodeString): UnicodeString;
var
  i, n: Integer;
begin
  Result := '';
  n := 0;
  i := 1;
  while i <= Length(bicim) do
  begin
    if (bicim[i] = '%') and (i < Length(bicim)) and
       ((bicim[i + 1] = 's') or (bicim[i + 1] = 'd')) then
    begin
      if n <= High(degerler) then
        Result := Result + degerler[n];
      Inc(n);
      Inc(i, 2);
    end
    else
    begin
      Result := Result + bicim[i];
      Inc(i);
    end;
  end;
end;

function KartSifirlamaMesaji(h: Byte; karttan: Boolean): UnicodeString;
var
  t, r: UnicodeString;
begin
  if h <= High(MsjHata) then
    t := MsjHata[h]
  else
    t := Bicimle(MsjBilinmeyenHata, [UnicodeString(IntToStr(h))]);
  if karttan then
    r := MsjKartSifirladi
  else
    r := MsjKartaSifirlama;
  Result := r + ' (kod=' + UnicodeString(IntToStr(h)) + ': ' + t + ')';
end;

end.
