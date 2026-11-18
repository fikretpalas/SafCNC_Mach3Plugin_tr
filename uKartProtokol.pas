{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uKartProtokol.pas - Arduino yazılımıyla ortak paket biçimi
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  PC -> kart: durum paketleri (8 bayt) ve hareket paketleri (10 bayt).
  Kart -> PC: her 50 ms'de bir durum paketi (8 bayt) ve kartın hız sınırını
  taşıyan bilgi paketi (K_BILGI, 8 bayt): açılışta, bağlantı zaman aşımında ve
  yeni bağlantının ilk K_SIFIRLA paketinde.
  Her paket: komut, sıra sayacı, veri ve 16 bit sağlama toplamı
  (tüm baytların toplamı sıfırdır).
}
unit uKartProtokol;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

const
  UNO_BAUD = 115200;
  UNO_DURUM_BOY = 8;
  UNO_HAREKET_BOY = 10;
  UNO_AZAMI_BOY = 10;
  UNO_EKSEN = 3;
  UNO_DILIM_SN = 0.005;
  UNO_ALT_VURUS = 160;
  // 5 ms dilimde eksen başına en fazla adım: 160 = 32 kHz (Arduino Uno / Nano).
  // Protokol Arduino'ya bağlı değildir: STM32 kart 500 = 100 kHz kullanabilir (test edilmedi).
  // Kart kendi sınırını K_BILGI paketiyle bildirir ve eklenti o değeri kullanır
  // (aşağıdaki KartAdimAzami); bu sabitler K_BILGI gelene kadar kullanılır.
  // Arduino Uno / Nano ise yaklaşık 30 kHz üzerine çıkamaz.
  UNO_ADIM_AZAMI = 160;
  // Protokol dilim başına hiçbir zaman 500 adımı (100 kHz, STM32 kart) geçmez.
  // Daha büyük bir değer bildiren kart bu değerle sınırlanır.
  UNO_ADIM_TAVANI = 500;
  // Tavanın adım hızı (saniyede 200 dilim): 100 kHz. Kart bağlı değilken
  // Mach3'e bu bildirilir; Motor Tuning'de hız buna kadar ayarlanabilir.
  UNO_TAVAN_HZ = UNO_ADIM_TAVANI * 200;
  UNO_TAMPON_AZAMI = 199;
  UNO_HIZLI_DILIM = 32;

  { Paket komutları; kart durumunu da aynı kodlarla bildirir }
  K_BILGI = 64;    // yalnızca kart -> PC: kart sınırları (bkz. BilgiCoz)
  K_SIFIRLA = 65;
  K_HAZIR = 66;
  K_KURULU = 67;
  K_HAREKET = 68;

  { Sıfırlama neden kodları }
  H_ACILIS = 0;
  H_ACILSTOP = 1;
  H_SIRA = 2;
  H_SAGLAMA = 3;
  H_KOMUT = 4;
  H_UZUNLUK = 5;
  H_ZAMANASIMI = 6;
  H_TASMA = 7;
  H_ADIMSINIRI = 8;
  H_YERELSTOP = 9;
  H_DURUM = 10;
  H_LIMIT = 11;
  H_PROB = 12;
  H_BOSALMA = 13;
  H_SON = 13;

  { Çıkış baytı bitleri (PC -> kart) }
  C_MIL_ACIK = $01;
  C_MIL_YON = $02;
  C_SOGUTMA = $04;
  C_SIS = $08;
  C_LIMITDUR = $10;
  C_PROBDUR = $20;
  C_BOSALMA = $40;
  C_CIKISLAR = $0F;
  C_MASKE = $7F;

  { Giriş baytı bitleri (kart -> PC) }
  G_LIMIT_X = $01;
  G_LIMIT_Y = $02;
  G_LIMIT_Z = $04;
  G_DURAKLAT = $08;
  G_BASLAT = $10;
  G_ACILSTOP = $20;
  G_PROB = $40;
  G_MASKE = $7F;

  CIKIS_PIN_SAYISI = 4;
  GIRIS_PIN_SAYISI = 7;
  LIMIT_PIN_SAYISI = 3;

type
  TPaket = array[0..UNO_AZAMI_BOY - 1] of Byte;
  TEksenTam = array[0..UNO_EKSEN - 1] of LongInt;

  { Karttan gelen çözülmüş durum paketi }
  TKartDurumu = record
    Durum: Byte;
    Sayac: Byte;
    Hata: Byte;
    DilimSayisi: Word;
    AltAdim: Byte;
    Tampon: Byte;
    Mil: Byte;
    CikisBitleri: Byte;
    GirisBitleri: Byte;
  end;

  { K_BILGI paketinden gelen kart hızı }
  TKartSinirlari = record
    AdimSiniri: Integer;    // 5 ms dilimde eksen başına en fazla adım (kart STEP_LIMIT)
    AltVurus: Integer;      // dilim başına alt vuruş (kart SUBTICKS)
    AzamiAdimHz: Integer;   // eksen başına en yüksek adım hızı, Hz = AdimSiniri x 200
    KarttanGeldi: Boolean;  // False = varsayılan değerler, kart henüz bildirmedi
  end;

var
  { Kullanılan sınırlar. Yalnızca Mach3 iş parçacığı (TKartKatmani) yazar,
    o da yalnızca kart SIFIRLA durumundayken: kart K_BILGI'yi sadece o zaman gönderir. }
  KartAdimAzami: Integer = UNO_ADIM_AZAMI;
  KartAltVurus: Integer = UNO_ALT_VURUS;

function BosDurum: TKartDurumu;
function VarsayilanBilgi: TKartSinirlari;
function BilgiCoz(const p: TPaket; out bilgi: TKartSinirlari): Boolean;
procedure KartBilgisiUygula(const bilgi: TKartSinirlari);
{ SIFIRLA durum paketindeki alt adımın paydası (bkz. BilgiCoz). }
function AltAdimOlcegi: Integer;
function PaketUzunlugu(k: Byte; karta: Boolean): Integer;
procedure SaglamaEkle(var p: TPaket; uzunluk: Integer);
function SaglamaDogru(const p: TPaket; uzunluk: Integer): Boolean;
procedure DurumPaketi(var p: TPaket; k, h, mil, cikis: Byte);
procedure HareketPaketi(var p: TPaket; x, y, z: Integer);
function PaketAdimlari(const p: TPaket; eksenNo: Integer): Integer;
function PaketCoz(const p: TPaket; out d: TKartDurumu): Boolean;
function KismiAdim(adimSayisi: Integer; altAdim: Byte): Integer;
function DurumLambaKodu(durum: Byte): Byte;

implementation

function BosDurum: TKartDurumu;
begin
  FillChar(Result, SizeOf(Result), 0);
end;

function VarsayilanBilgi: TKartSinirlari;
begin
  Result.AdimSiniri := UNO_ADIM_AZAMI;
  Result.AltVurus := UNO_ALT_VURUS;
  Result.AzamiAdimHz := Round(UNO_ADIM_AZAMI / UNO_DILIM_SN);
  Result.KarttanGeldi := False;
end;

{ K_BILGI (kart -> PC, 8 bayt):
    p[2..3] = STEP_LIMIT, p[4..5] = SUBTICKS (ikisi de 16 bit, önce yüksek bayt).
  Arduino Uno / Nano: 160 / 160 = 32 kHz; STM32 kart en fazla 500 = 100 kHz.
  Adım sınırı hiçbir zaman UNO_ADIM_TAVANI'nın ve alt vuruş sayısının üstüne
  çıkarılmaz (kartın DDA'sı her vuruşta en fazla bir adım atar). }
function BilgiCoz(const p: TPaket; out bilgi: TKartSinirlari): Boolean;
var
  adim, vurus: Integer;
begin
  bilgi := VarsayilanBilgi;
  Result := False;
  if p[0] <> K_BILGI then Exit;
  if not SaglamaDogru(p, UNO_DURUM_BOY) then Exit;
  adim := (Integer(p[2]) shl 8) or p[3];
  vurus := (Integer(p[4]) shl 8) or p[5];
  if (adim < 1) or (vurus < 1) then Exit;
  if adim > UNO_ADIM_TAVANI then adim := UNO_ADIM_TAVANI;
  if adim > vurus then adim := vurus;
  bilgi.AdimSiniri := adim;
  bilgi.AltVurus := vurus;
  bilgi.AzamiAdimHz := Round(adim / UNO_DILIM_SN);
  bilgi.KarttanGeldi := True;
  Result := True;
end;

procedure KartBilgisiUygula(const bilgi: TKartSinirlari);
begin
  KartAdimAzami := bilgi.AdimSiniri;
  KartAltVurus := bilgi.AltVurus;
end;

{ SIFIRLA durum paketindeki alt adım tek bayttır. 255'ten fazla alt vuruşu
  olan kart onu 0..255 aralığına ölçekleyerek gönderir (alt * 256 / SUBTICKS). }
function AltAdimOlcegi: Integer;
begin
  if KartAltVurus > 255 then Result := 256 else Result := KartAltVurus;
end;

function PaketUzunlugu(k: Byte; karta: Boolean): Integer;
begin
  case k of
    K_BILGI:
      if karta then Result := 0 else Result := UNO_DURUM_BOY;
    K_SIFIRLA, K_HAZIR, K_KURULU:
      Result := UNO_DURUM_BOY;
    K_HAREKET:
      if karta then Result := UNO_HAREKET_BOY else Result := UNO_DURUM_BOY;
  else
    Result := 0;
  end;
end;

function Toplam16(const p: TPaket; uzunluk: Integer): Word;
var
  s: DWord;
  i: Integer;
begin
  s := 0;
  for i := 0 to uzunluk - 3 do
    s := s + p[i];
  Result := Word(s and $FFFF);
end;

procedure SaglamaEkle(var p: TPaket; uzunluk: Integer);
var
  m: Word;
begin
  m := Word((DWord($10000) - Toplam16(p, uzunluk)) and $FFFF);
  p[uzunluk - 2] := Byte(m shr 8);
  p[uzunluk - 1] := Byte(m and $FF);
end;

function SaglamaDogru(const p: TPaket; uzunluk: Integer): Boolean;
var
  m: DWord;
begin
  m := (DWord(p[uzunluk - 2]) shl 8) or p[uzunluk - 1];
  Result := ((DWord(Toplam16(p, uzunluk)) + m) and $FFFF) = 0;
end;

procedure DurumPaketi(var p: TPaket; k, h, mil, cikis: Byte);
begin
  FillChar(p, SizeOf(p), 0);
  p[0] := k;
  if k = K_SIFIRLA then
  begin
    if h > H_SON then h := H_ACILIS;
    p[2] := h;
  end
  else
  begin
    p[3] := mil;
    p[4] := cikis and C_MASKE;
  end;
end;

function AdimSinirla(v: Integer): Integer;
begin
  if v > KartAdimAzami then Exit(KartAdimAzami);
  if v < -KartAdimAzami then Exit(-KartAdimAzami);
  Result := v;
end;

procedure AdimYaz(var p: TPaket; i, v: Integer);
var
  en: Word;
begin
  en := Word(SmallInt(AdimSinirla(v)));
  p[i] := Byte(en shr 8);
  p[i + 1] := Byte(en and $FF);
end;

procedure HareketPaketi(var p: TPaket; x, y, z: Integer);
begin
  FillChar(p, SizeOf(p), 0);
  p[0] := K_HAREKET;
  AdimYaz(p, 2, x);
  AdimYaz(p, 4, y);
  AdimYaz(p, 6, z);
end;

function PaketAdimlari(const p: TPaket; eksenNo: Integer): Integer;
var
  en: Word;
begin
  en := Word((Word(p[2 + eksenNo * 2]) shl 8) or p[3 + eksenNo * 2]);
  Result := SmallInt(en);
end;

function PaketCoz(const p: TPaket; out d: TKartDurumu): Boolean;
begin
  d := BosDurum;
  Result := False;
  if p[0] = K_BILGI then Exit;   // durum paketi değil, bkz. BilgiCoz
  if PaketUzunlugu(p[0], False) <> UNO_DURUM_BOY then Exit;
  if not SaglamaDogru(p, UNO_DURUM_BOY) then Exit;
  d.Durum := p[0];
  d.Sayac := p[1];
  if p[0] = K_SIFIRLA then
  begin
    d.Hata := p[2];
    d.DilimSayisi := Word((Word(p[3]) shl 8) or p[4]);
    d.AltAdim := p[5];
  end
  else
  begin
    d.Tampon := p[2];
    if d.Tampon > UNO_TAMPON_AZAMI then d.Tampon := UNO_TAMPON_AZAMI;
    d.Mil := p[3];
    d.CikisBitleri := p[4] and C_MASKE;
    d.GirisBitleri := p[5] and G_MASKE;
  end;
  Result := True;
end;

{ Kesilen dilimde altAdim alt-adımına kadar yürütülmüş adım sayısı. }
function KismiAdim(adimSayisi: Integer; altAdim: Byte): Integer;
begin
  if adimSayisi >= 0 then
    Result := (adimSayisi * altAdim) div AltAdimOlcegi
  else
    Result := -((-adimSayisi * altAdim) div AltAdimOlcegi);
end;

{ Durum penceresi lamba renk kodu. }
function DurumLambaKodu(durum: Byte): Byte;
begin
  case durum of
    K_SIFIRLA: Result := 0;
    K_HAZIR, K_KURULU: Result := 1;
    K_HAREKET: Result := 6;
  else
    Result := 255;
  end;
end;

end.
