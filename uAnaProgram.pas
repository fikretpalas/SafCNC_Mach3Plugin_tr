{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uAnaProgram.pas - Mach3 iç yapılarına erişim
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  Paylaşılan Engine ve MainPlanner bellek blokları, Mach3 geri çağırma
  işlevleri, durum satırı ve Ports & Pins sinyal tabloları.
  Eklenti kalıcı ayar tutmaz ve kayıt defterine hiçbir şey yazmaz.
  ENG_ / PLN_ değerleri, eklentinin yazıldığı 32 bit Mach3 sürümünde Engine
  ve MainPlanner bloklarının içindeki konumlardır.
}
unit uAnaProgram;

{$mode objfpc}{$H+}
{$codepage utf8}
{$R-}{$Q-}

interface

uses
  Windows, SysUtils, Math, uSistemApi, uMesajlar, uKartProtokol;

const
  EKSEN_SAYISI = 4;

  { ---- Mach3 bellek düzeni ---- }
  HARICI_VMS = 1;
  ENG_YORUNGE_ARALIK = 40;
  ENG_YORUNGE_KIMLIK = 28;
  ENG_YORUNGE_SIRA = 163840;
  ENG_YORUNGE_BAS = 163844;
  ENG_EKSEN = 163920;
  ENG_EKSEN_ARALIK = 96;
  EKS_SIRA = 0;
  EKS_YAVASLAMA = 34;
  EKS_JOG = 36;
  ENG_JOG_ETKIN = 163908;
  ENG_ESITLE = 163910;
  ENG_GOSTERILEN_SATIR = 166500;
  PLN_HAREKETLER = 1177752;
  GMOVES_BOYU = 288;
  GM_BITIS = 32;
  GM_BASLANGIC = 80;
  PLN_JOG_ETKIN = 801965;
  PLN_ADIM_BIRIMI = 586904;
  PLN_HIZLAR = 586952;
  PLN_IVME = 587000;
  PLN_HARICI_DARBE_HIZI = 2384280;
  PLN_HARICI_DURUYOR = 2384336;
  PLN_HARICI_TIP = 2384726;
  PLN_TAMPON_BITIYOR = 2745176;
  PLN_HARICI_SURE = 2745184;
  PLN_HARICI_TAMPON_UST = 2745192;
  GORUNUM_YAZICI_ACIK = 133936;

  { ---- Sıfırlama, mesajlar ve sinyal tabloları ---- }
  SIFIRLAMA_NEDENI_BEKCI = 3;
  SIFIRLAMA_NEDENI_LIMIT = 4;
  SIFIRLAMA_NEDENI_KART = 6;
  MESAJ_GENEL = 0;
  MESAJ_BAGLANTI = 1;
  MESAJ_TERS_TUS = 2;
  ENG_SIFIRLAMA_BAYRAGI = $289DF;
  ENG_SIFIRLAMA_NEDENI = $28B50;
  ENG_LIMIT_ATLAMA = $28B35;
  ENG_GIRIS_TABAN = $282F0;
  ENG_GIRIS_SAYISI = 53;
  ENG_GIRIS_ARALIK = 16;
  ENG_LIMIT_SINYALLERI = 18;
  ENG_CIKIS_TABAN = $28640;
  ENG_CIKIS_SAYISI = 30;
  ENG_CIKIS_ARALIK = 5;
  ENG_BENZETIM_MODU = $28D6E;
  ENG_PROB_ACIK = $28450;
  ENG_PROB_DURUMU = $28A5C;
  ENG_BEKLEME_BAYRAGI = $28A4C;
  ENG_JOG_MESGUL = $28044;
  PLN_HARICI_AYGIT = $246188;
  PLN_BAYRAK_29E376 = $29E376;
  PLN_BAYRAK_2462F0 = $2462F0;
  PLN_PROB_BAYRAGI = $11DDA0;
  PLN_BEKLEME_MS = $11E03D;
  KART_PORTU = 3;
  OEM_SIFIRLA = 1021;

type
  { Mach3 planlayıcı tamponundaki bir yörünge noktası (32 bit Mach3'te 288 bayt).
    ex..ec eksen konumları (adım). }
  TGMoves = packed record
    MoveType: LongInt;
    Dolgu0: LongInt;
    cx, cy, cz: Double;
    ex, ey, ez, ea, eb, ec: Double;
    sx, sy, sz, sa, sb, sc: Double;
    Dolgu1: array[0..143] of Byte;
    Time: Double;
    Stop: Byte;
    Dolgu2: array[0..6] of Byte;
  end;
  PGMoves = ^TGMoves;

  { Mach3 geri çağırma işlevleri (cdecl) }
  TYordamKisa = procedure(code: SmallInt); cdecl;
  TTamKisa = function(count: SmallInt): Integer; cdecl;
  TReelKisa = function(code: SmallInt): Double; cdecl;
  TYordamKisaReel = procedure(code: SmallInt; deger: Double); cdecl;
  TMantikKisa = function(code: SmallInt): ByteBool; cdecl;
  TYordamKisaMantik = procedure(code: SmallInt; deger: ByteBool); cdecl;
  TYordamMetin = procedure(metin: PAnsiChar); cdecl;

  { Mach3 durumunu okuyan ve yazan yöntemler }
  TAnaProgram = class
  public
    function AdimBirimi(eksenNo: Integer): Double;
    function Ivme(eksenNo: Integer): Double;
    function KonumVar: Boolean;
    function KonumOku(eksenNo: Integer): Integer;
    procedure KonumYaz(eksenNo, yeniDeger: Integer);
    function SifirlamaBilgisiVar: Boolean;
    function Sifirlamada: Boolean;
    procedure SifirlamayaAl(neden: Integer);
    procedure SifirlamaDugmesineBas;
    function CikisMaskesi(out kapsanan: Byte): Byte;
    function GirisleriAktar(girisler: Byte): Boolean;
    function LimitDurdurur: Boolean;
    function MilGucu: Byte;
    procedure GkodBitti;
    procedure SurucuyuAyarla(cekirdekKHz, tamponUst: Integer; dilimSaniye: Double);
    procedure MesajGoster(const mesajMetni: UnicodeString);
    procedure SureliMesaj(const mesajMetni: UnicodeString; mesajKimlik: Integer; sureMs: DWord);
    procedure MesajiKaldir(mesajKimlik: Integer);
    procedure HareketAdimlari(const hareket: TGMoves; var adimSayisi: array of Double);
  end;

var
  DoButton: TYordamKisa = nil;
  GetMenuRange: TTamKisa = nil;
  GetDRO: TReelKisa = nil;
  SetDRO: TYordamKisaReel = nil;
  GetLED: TMantikKisa = nil;
  SetLED: TYordamKisaMantik = nil;
  Code: TYordamMetin = nil;
  ProfilAdi: AnsiString = '';
  Engine: Pointer = nil;
  AyarBlogu: Pointer = nil;
  MainPlanner: Pointer = nil;
  GorunumBlogu: Pointer = nil;

{ ---- Mach3 bellek erişimi ---- }
function DuzenGecerli: Boolean;
function KaymaAdres(b: Pointer; kayma: PtrInt): PByte; inline;
function MantikOku(p: PByte): Boolean; inline;
procedure MantikYaz(p: PByte; deger: Boolean); inline;
function EngYorungeSira: PLongInt;
function EngYorungeBas: PLongInt;
function EngGosterilenSatir: PLongInt;
function EngYorungeKimlik(sira: Integer): PLongInt;
function EngEksenSira(eksen: Integer): PLongInt;
function EngEksenYavaslama(eksen: Integer): PByte;
function EngEksenJog(eksen: Integer): PByte;
function EngJogEtkin: PByte;
function EngEsitle: PByte;
function PlnHareket(sira: Integer): PGMoves;
function PlnHariciTamponUst: PLongInt;
function PlnHariciSure: PDouble;
function PlnHariciTip: PSmallInt;
function PlnHariciDarbeHizi(eksen: Integer): PDouble;
function PlnHariciDuruyor: PByte;
function PlnTamponBitiyor: PByte;
function PlnJogEtkin: PByte;
function PlnHiz(eksen: Integer): PDouble;
function PlnIvme(eksen: Integer): PDouble;
function PlnAdimBirimi(eksen: Integer): PDouble;
function GorunumYaziciAcik: PByte;

{ ---- Durum satırı ve durum sorguları ---- }
function EngAdres(kayma: Integer): PByte;
function PlnAdres(kayma: Integer): PByte;
function ProgramSifirlamada: Boolean;
function ProgramBenzetimde: Boolean;
procedure DurumMesaji(const mesajMetni: UnicodeString; mesajKimlik: Integer = MESAJ_GENEL;
  sureMs: DWord = 0);
procedure DurumMesajiniSil(mesajKimlik: Integer);
procedure DurumMesajiniErtele(yenileme: Integer);
procedure DurumMesajiHizmeti;

implementation

var
  gDuzenTamam: Boolean = False;
  gMesajKimlik: Integer = MESAJ_GENEL;
  gMesajBitis: QWord = 0;
  gMesajErtele: Integer = 0;
  gMesajBekliyor: Boolean = False;
  gMesajBekleyen: UnicodeString = '';
  gMesajBekleyenMs: DWord = 0;

{ ================= Mach3 bellek erişimi ================= }

function DuzeniHesapla: Boolean;
var
  g: TGMoves;
begin
  Result := (SizeOf(Pointer) = 4) and
    (SizeOf(TGMoves) = GMOVES_BOYU) and
    (PtrUInt(@g.ex) - PtrUInt(@g) = GM_BITIS) and
    (PtrUInt(@g.sx) - PtrUInt(@g) = GM_BASLANGIC);
end;

function DuzenGecerli: Boolean;
begin
  Result := gDuzenTamam;
end;

function KaymaAdres(b: Pointer; kayma: PtrInt): PByte; inline;
begin
  Result := PByte(PtrUInt(b) + PtrUInt(kayma));
end;

function MantikOku(p: PByte): Boolean; inline;
begin
  Result := p^ <> 0;
end;

procedure MantikYaz(p: PByte; deger: Boolean); inline;
begin
  if deger then p^ := 1 else p^ := 0;
end;

function EngYorungeSira: PLongInt;
begin
  Result := PLongInt(KaymaAdres(Engine, ENG_YORUNGE_SIRA));
end;

function EngYorungeBas: PLongInt;
begin
  Result := PLongInt(KaymaAdres(Engine, ENG_YORUNGE_BAS));
end;

function EngGosterilenSatir: PLongInt;
begin
  Result := PLongInt(KaymaAdres(Engine, ENG_GOSTERILEN_SATIR));
end;

function EngYorungeKimlik(sira: Integer): PLongInt;
begin
  Result := PLongInt(KaymaAdres(Engine, (sira and $FFF) * ENG_YORUNGE_ARALIK + ENG_YORUNGE_KIMLIK));
end;

function EngEksenSira(eksen: Integer): PLongInt;
begin
  Result := PLongInt(KaymaAdres(Engine, ENG_EKSEN + eksen * ENG_EKSEN_ARALIK + EKS_SIRA));
end;

function EngEksenYavaslama(eksen: Integer): PByte;
begin
  Result := KaymaAdres(Engine, ENG_EKSEN + eksen * ENG_EKSEN_ARALIK + EKS_YAVASLAMA);
end;

function EngEksenJog(eksen: Integer): PByte;
begin
  Result := KaymaAdres(Engine, ENG_EKSEN + eksen * ENG_EKSEN_ARALIK + EKS_JOG);
end;

function EngJogEtkin: PByte;
begin
  Result := KaymaAdres(Engine, ENG_JOG_ETKIN);
end;

function EngEsitle: PByte;
begin
  Result := KaymaAdres(Engine, ENG_ESITLE);
end;

function PlnHareket(sira: Integer): PGMoves;
begin
  Result := PGMoves(KaymaAdres(MainPlanner, PLN_HAREKETLER + (sira and $FFF) * GMOVES_BOYU));
end;

function PlnHariciTamponUst: PLongInt;
begin
  Result := PLongInt(KaymaAdres(MainPlanner, PLN_HARICI_TAMPON_UST));
end;

function PlnHariciSure: PDouble;
begin
  Result := PDouble(KaymaAdres(MainPlanner, PLN_HARICI_SURE));
end;

function PlnHariciTip: PSmallInt;
begin
  Result := PSmallInt(KaymaAdres(MainPlanner, PLN_HARICI_TIP));
end;

function PlnHariciDarbeHizi(eksen: Integer): PDouble;
begin
  Result := PDouble(KaymaAdres(MainPlanner, PLN_HARICI_DARBE_HIZI + eksen * 8));
end;

function PlnHariciDuruyor: PByte;
begin
  Result := KaymaAdres(MainPlanner, PLN_HARICI_DURUYOR);
end;

function PlnTamponBitiyor: PByte;
begin
  Result := KaymaAdres(MainPlanner, PLN_TAMPON_BITIYOR);
end;

function PlnJogEtkin: PByte;
begin
  Result := KaymaAdres(MainPlanner, PLN_JOG_ETKIN);
end;

function PlnHiz(eksen: Integer): PDouble;
begin
  Result := PDouble(KaymaAdres(MainPlanner, PLN_HIZLAR + eksen * 8));
end;

function PlnIvme(eksen: Integer): PDouble;
begin
  Result := PDouble(KaymaAdres(MainPlanner, PLN_IVME + eksen * 8));
end;

function PlnAdimBirimi(eksen: Integer): PDouble;
begin
  Result := PDouble(KaymaAdres(MainPlanner, PLN_ADIM_BIRIMI + eksen * 8));
end;

function GorunumYaziciAcik: PByte;
begin
  Result := KaymaAdres(GorunumBlogu, GORUNUM_YAZICI_ACIK);
end;

{ ================= Durum satırı ve durum sorguları ================= }

function EngAdres(kayma: Integer): PByte;
begin
  Result := KaymaAdres(Engine, kayma);
end;

function PlnAdres(kayma: Integer): PByte;
begin
  Result := KaymaAdres(MainPlanner, kayma);
end;

function EngHazir: Boolean;
begin
  Result := (Engine <> nil) and DuzenGecerli;
end;

function ProgramSifirlamada: Boolean;
begin
  Result := EngHazir and (EngAdres(ENG_SIFIRLAMA_BAYRAGI)^ <> 0);
end;

function ProgramBenzetimde: Boolean;
begin
  Result := (Engine <> nil) and (EngAdres(ENG_BENZETIM_MODU)^ <> 0);
end;

function LimitAtlamaEtkin: Boolean;
begin
  Result := EngHazir and (EngAdres(ENG_LIMIT_ATLAMA)^ <> 0);
end;

{ Mach3 durum satırına yazar. Mach3 orada G-kod açıklaması gösterdiği için
  ( ) ve virgül çıkarılır. }
procedure MesajYaz(const mesajMetni: UnicodeString);
var
  s: UnicodeString;
  a: AnsiString;
  i: Integer;
  c: WideChar;
begin
  if not Assigned(Code) then Exit;
  s := '';
  for i := 1 to Length(mesajMetni) do
  begin
    c := mesajMetni[i];
    if (c <> '(') and (c <> ')') and (c <> ',') and (c >= ' ') then
      s := s + c;
  end;
  if s = '' then s := ' ';
  a := AnsiString('(' + s + ')');
  try
    Code(PAnsiChar(a));
  except
  end;
end;

procedure MesajSuresiKur(sureMs: DWord);
begin
  if sureMs > 0 then
    gMesajBitis := SaatMs64 + sureMs
  else
    gMesajBitis := 0;
end;

procedure DurumMesaji(const mesajMetni: UnicodeString; mesajKimlik: Integer; sureMs: DWord);
begin
  gMesajKimlik := mesajKimlik;
  if gMesajErtele > 0 then
  begin
    gMesajBekliyor := True;
    gMesajBekleyen := mesajMetni;
    gMesajBekleyenMs := sureMs;
    gMesajBitis := 0;
    Exit;
  end;
  MesajYaz(mesajMetni);
  MesajSuresiKur(sureMs);
end;

procedure DurumMesajiniSil(mesajKimlik: Integer);
begin
  if (mesajKimlik = MESAJ_GENEL) or (gMesajKimlik <> mesajKimlik) then Exit;
  DurumMesaji('', MESAJ_GENEL, 0);
end;

procedure DurumMesajiniErtele(yenileme: Integer);
begin
  if yenileme > gMesajErtele then gMesajErtele := yenileme;
end;

{ Her güncelleme döngüsünde çağrılır: geciken mesajları gösterir, süresi dolanları siler. }
procedure DurumMesajiHizmeti;
begin
  if gMesajErtele > 0 then
  begin
    Dec(gMesajErtele);
    if (gMesajErtele = 0) and gMesajBekliyor then
    begin
      gMesajBekliyor := False;
      MesajYaz(gMesajBekleyen);
      MesajSuresiKur(gMesajBekleyenMs);
    end;
    Exit;
  end;
  if (gMesajBitis <> 0) and (SaatMs64 >= gMesajBitis) then
  begin
    gMesajBitis := 0;
    gMesajKimlik := MESAJ_GENEL;
    MesajYaz('');
  end;
end;

{ Mach3 giriş sinyal tablosu (Ports & Pins) yardımcıları }
function GirisKaydi(sira: Integer): PByte;
begin
  Result := EngAdres(ENG_GIRIS_TABAN + sira * ENG_GIRIS_ARALIK);
end;

function GirisPini(sira: Integer): Integer;
var
  e: PByte;
begin
  e := GirisKaydi(sira);
  if (e[0] <> 0) and (e[2] = KART_PORTU) and (e[1] >= 1) and (e[1] <= GIRIS_PIN_SAYISI) then
    Result := e[1]
  else
    Result := 0;
end;

function GirisDusukEtkin(sira: Integer): Boolean;
var
  e: PByte;
begin
  e := GirisKaydi(sira);
  Result := e[3] <> 0;
end;

function EksenLimiti(sira: Integer): Boolean;
begin
  Result := (sira < ENG_LIMIT_SINYALLERI) and ((sira mod 3) <> 2);
end;

function ReferansAyniPinde(sira, pin: Integer): Boolean;
begin
  Result := GirisPini((sira div 3) * 3 + 2) = pin;
end;

{ ================= TAnaProgram ================= }

function TAnaProgram.AdimBirimi(eksenNo: Integer): Double;
begin
  if MainPlanner = nil then Exit(0);
  Result := PlnAdimBirimi(eksenNo)^;
  if IsNan(Result) or IsInfinite(Result) or (Result <= 0) then Result := 0;
end;

function TAnaProgram.Ivme(eksenNo: Integer): Double;
begin
  if MainPlanner = nil then Exit(0);
  Result := PlnIvme(eksenNo)^;
  if IsNan(Result) or IsInfinite(Result) or (Result <= 0) then Result := 0;
end;

function TAnaProgram.KonumVar: Boolean;
begin
  Result := Engine <> nil;
end;

function TAnaProgram.KonumOku(eksenNo: Integer): Integer;
begin
  Result := EngEksenSira(eksenNo)^;
end;

procedure TAnaProgram.KonumYaz(eksenNo, yeniDeger: Integer);
begin
  EngEksenSira(eksenNo)^ := yeniDeger;
end;

function TAnaProgram.SifirlamaBilgisiVar: Boolean;
begin
  Result := EngHazir;
end;

function TAnaProgram.Sifirlamada: Boolean;
begin
  Result := ProgramSifirlamada;
end;

procedure TAnaProgram.SifirlamayaAl(neden: Integer);
begin
  if not EngHazir then Exit;
  EngAdres(ENG_SIFIRLAMA_BAYRAGI)^ := 1;
  PLongInt(EngAdres(ENG_SIFIRLAMA_NEDENI))^ := neden;
end;

{ Mach3 Reset düğmesine basar (Mach3'ü acil stop'a alır). }
procedure TAnaProgram.SifirlamaDugmesineBas;
begin
  if not Assigned(DoButton) then Exit;
  try
    DoButton(OEM_SIFIRLA);
  except
  end;
end;

{ Mach3'ten fener mili ve soğutma durumlarını okuyup kart çıkış baytını kurar. }
function TAnaProgram.CikisMaskesi(out kapsanan: Byte): Byte;
var
  i, pin: Integer;
  e: PByte;
  bit: Byte;
  acik: Boolean;
begin
  Result := 0;
  kapsanan := 0;
  if not EngHazir then Exit;
  for i := 0 to ENG_CIKIS_SAYISI - 1 do
  begin
    e := EngAdres(ENG_CIKIS_TABAN + i * ENG_CIKIS_ARALIK);
    if (e[0] = 0) or (e[2] <> KART_PORTU) then Continue;
    pin := e[1];
    if (pin < 1) or (pin > CIKIS_PIN_SAYISI) then Continue;
    bit := Byte(1 shl (pin - 1));
    kapsanan := kapsanan or bit;
    if e[4] <> 0 then acik := e[3] = 0 else acik := e[3] <> 0;
    if acik then Result := Result or bit
    else Result := Result and not bit;
  end;
end;

{ Kart girişlerini (limit, prob, düğmeler) Mach3 giriş sinyallerine kopyalar.
  Bir limit anahtarı sıfırlama gerektiriyorsa True döner. }
function TAnaProgram.GirisleriAktar(girisler: Byte): Boolean;
var
  i, pin: Integer;
  e: PByte;
  denetle, etkin, temiz: Boolean;
begin
  Result := False;
  if not EngHazir then Exit;
  denetle := (not ProgramSifirlamada) and (not LimitAtlamaEtkin);
  for i := 0 to ENG_GIRIS_SAYISI - 1 do
  begin
    pin := GirisPini(i);
    if pin = 0 then Continue;
    e := GirisKaydi(i);
    etkin := ((girisler shr (pin - 1)) and 1) <> 0;
    if e[3] <> 0 then etkin := not etkin;
    if etkin then e[8] := 1 else e[8] := 0;
    if denetle and etkin and EksenLimiti(i) and (not ReferansAyniPinde(i, pin)) then
      Result := True;
  end;
  if LimitAtlamaEtkin then
  begin
    temiz := True;
    for i := 0 to ENG_LIMIT_SINYALLERI - 1 do
    begin
      if not EksenLimiti(i) then Continue;
      e := GirisKaydi(i);
      if (e[0] <> 0) and (e[8] <> 0) then temiz := False;
    end;
    if temiz then
    begin
      EngAdres(ENG_LIMIT_ATLAMA)^ := 0;
      DurumMesaji(MsjLimitAtlamaBitti);
    end;
  end;
end;

{ Limit anahtarları kartı hemen durdurmalı mı (limit atlama modunda değilken). }
function TAnaProgram.LimitDurdurur: Boolean;
var
  i, pin: Integer;
  limitler, digerleri, bit: Byte;
begin
  Result := False;
  if (not EngHazir) or LimitAtlamaEtkin then Exit;
  limitler := 0;
  digerleri := 0;
  for i := 0 to ENG_GIRIS_SAYISI - 1 do
  begin
    pin := GirisPini(i);
    if (pin = 0) or (pin > LIMIT_PIN_SAYISI) then Continue;
    bit := Byte(1 shl (pin - 1));
    if EksenLimiti(i) and (not GirisDusukEtkin(i)) and (not ReferansAyniPinde(i, pin)) then
      limitler := limitler or bit
    else
      digerleri := digerleri or bit;
  end;
  Result := (limitler <> 0) and (digerleri = 0);
end;

function TAnaProgram.MilGucu: Byte;
begin
  Result := 255;
end;

procedure TAnaProgram.GkodBitti;
begin
  if MainPlanner <> nil then MantikYaz(PlnHariciDuruyor, True);
end;

{ Mach3 planlayıcısına harici hareket aygıtı kullanıldığını bildirir,
  dilim süresini ve tampon boyunu ayarlar. }
procedure TAnaProgram.SurucuyuAyarla(cekirdekKHz, tamponUst: Integer; dilimSaniye: Double);
var
  hz: Double;
  i: Integer;
begin
  if MainPlanner = nil then Exit;
  hz := cekirdekKHz * 1000.0;
  for i := 0 to 6 do PlnHariciDarbeHizi(i)^ := hz;
  PlnHariciTamponUst^ := tamponUst;
  PlnHariciSure^ := dilimSaniye;
  PlnHariciTip^ := HARICI_VMS;
  PlnAdres(PLN_HARICI_AYGIT)^ := 1;
  PlnAdres(PLN_BAYRAK_29E376)^ := 0;
  PlnAdres(PLN_BAYRAK_2462F0)^ := 1;
end;

procedure TAnaProgram.MesajGoster(const mesajMetni: UnicodeString);
begin
  DurumMesaji(mesajMetni);
end;

procedure TAnaProgram.SureliMesaj(const mesajMetni: UnicodeString; mesajKimlik: Integer; sureMs: DWord);
begin
  DurumMesaji(mesajMetni, mesajKimlik, sureMs);
end;

procedure TAnaProgram.MesajiKaldir(mesajKimlik: Integer);
begin
  DurumMesajiniSil(mesajKimlik);
end;

{ Bir yörünge noktasının adım konumlarını alır. }
procedure TAnaProgram.HareketAdimlari(const hareket: TGMoves; var adimSayisi: array of Double);
begin
  if High(adimSayisi) >= 0 then adimSayisi[0] := hareket.ex;
  if High(adimSayisi) >= 1 then adimSayisi[1] := hareket.ey;
  if High(adimSayisi) >= 2 then adimSayisi[2] := hareket.ez;
  if High(adimSayisi) >= 3 then adimSayisi[3] := hareket.ea;
end;

initialization
  gDuzenTamam := DuzeniHesapla;

end.
