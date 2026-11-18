{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uSeriBaglanti.pas - karta USB seri bağlantı
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  Kartı herhangi bir COM portunda bulur, portu çakışmalı (overlapped) G/Ç
  ile açar ve Mach3 hiçbir zaman USB'yi beklemesin diye ayrı okuma ve yazma
  iş parçacıkları çalıştırır. Her paketi (uzunluk, sağlama toplamı, sıra) ve
  200 ms bağlantı zaman aşımını denetler.
}
unit uSeriBaglanti;

{$mode objfpc}{$H+}
{$codepage utf8}
{$R-}{$Q-}

interface

uses
  Windows, Classes, SysUtils, Registry, uSistemApi, uMesajlar, uKartProtokol;

const
  SER_KUYRUK_BOYU = 1024;
  SER_GECMIS = 1024;
  SER_ALMA_ZAMAN_ASIMI_MS = 1500;
  SER_ACILIS_BEKLEME_MS = 3000;
  SER_ACILIS_BEKLEME_KART_MS = 8000;
  SER_YENIDEN_ACMA_MS = 500;
  SER_TERCIH_DENEME = 6;
  SER_ACILIS_BEKLEME_TAZE_MS = 2500;
  SER_TAZE_BEKLEME_MS = 1000;
  SER_AYAR_ZAMAN_ASIMI_MS = 6000;
  SER_TAZE_DENEME = 3;
  SER_YAZMA_ZAMAN_ASIMI_MS = 300;
  SER_YAZMA_DENEME = 3;
  SER_OKUMA_ZAMAN_ASIMI_MS = 25;
  SER_DURUM_MS = 50;
  SER_KURULUM_ZAMAN_ASIMI_MS = 200;
  SER_KURULUM_TOLERANS_MS = 250;
  SER_BAYT_ARASI_MS = 30;
  HK_PC = 0;
  HK_KART = 1;
  OKUMA_TAMPON_BOYU = 64;

type
  TSeriBaglanti = class;

  { Okuma ya da yazma döngüsünü çalıştıran iş parçacığı }
  TBaglantiIsParcacigi = class(TThread)
  private
    FSahip: TSeriBaglanti;
    FOkuyucu: Boolean;
  protected
    procedure Execute; override;
  public
    constructor Create(ASahip: TSeriBaglanti; AOkuyucu: Boolean);
  end;

  TSeriBaglanti = class
  private
    FKilit: TRTLCriticalSection;
    FTutamac: THandle;
    FOkumaOv: TOverlapped_;
    FYazmaOv: TOverlapped_;
    FOkumaTamponu: array[0..OKUMA_TAMPON_BOYU - 1] of Byte;
    FYazmaTamponu: TPaket;
    FOkumaBekliyor: Boolean;
    FYazmaIsi, FOkumaIsi: TBaglantiIsParcacigi;
    FIsDur: Boolean;
    FUyandir: THandle;
    FDuruyor: Boolean;
    FBagli: Boolean;
    FGoruldu: Boolean;
    FYaziyor: Boolean;
    FPortAdi: string;
    FTercih: string;
    FAdaySira: Integer;
    FGorulmustu: Boolean;
    FAcilisBekleme: QWord;
    FTercihYok: Boolean;
    FTercihHata: Integer;
    FTazeDeneme: Integer;
    FTazeZaman: QWord;
    FPortListesi: TStringList;
    FYeniPortNo: DWord;
    FAyarBekliyor: Boolean;
    FAyarBaslangic: QWord;
    FAyarDeneme: Integer;
    FSonHata: UnicodeString;
    FKuyruk: array[0..SER_KUYRUK_BOYU - 1] of TPaket;
    FBas, FAdet: Integer;
    FNesil: DWord;
    FAlmaPenceresi: TPaket;
    FAlinanPaket: TPaket;
    FGidenPaket: TPaket;
    FAlmaAdet: Integer;
    FBozukBayt: DWord;
    FDurum: TKartDurumu;
    FDurumNo: DWord;
    FBilgi: TKartSinirlari;
    FBilgiNo: DWord;
    FAlmaZamani, FAcilisZamani, FSonDeneme: QWord;
    FHassasSayac: Boolean;
    FDilim: Int64;
    FMsBasina: Int64;
    FModelDerinlik: Integer;
    FModelZaman: Int64;
    FZamanlayiciAcik: Boolean;
    FGidenKomut, FGidenKod, FGidenMil, FGidenBit, FGidenNo: Byte;
    FBaglantiIstegi: Boolean;
    FKartSifirlamada: Boolean;
    FSifirlamaOnay: Boolean;
    FDurumHemen: Boolean;
    FSonDurumMs: Int64;
    FKurulumMs: Int64;
    FAlmaMs: Int64;
    FSonBaytMs: Int64;
    FAlmaNo: Byte;
    FAlmaEsit: Boolean;
    FHataNo, FHataAlinan: DWord;
    FHataKodu, FHataKaynagi: Byte;
    FOturum: Boolean;
    FOturumKart: Boolean;
    FOturumKod: Byte;
    FYazilan: Int64;
    FSonDilimMs: Int64;
    FYazilanToplam: array[0..UNO_EKSEN - 1] of Int64;
    FKabulToplam: array[0..UNO_EKSEN - 1] of Int64;
    FGecmis: array[0..SER_GECMIS - 1, 0..UNO_EKSEN - 1] of SmallInt;
    FFark: array[0..UNO_EKSEN - 1] of Int64;
    FFarkVar: Boolean;
    FFarkBelirsiz: Boolean;

    procedure Kilitle; inline;
    procedure KilidiAc; inline;
    function SayacSimdi: Int64;
    function SimdiMs: Int64;
    function AdaylariOlustur: TStringList;
    procedure PortListesiniIzle(l: TStringList);
    function TercihListede: Boolean;
    procedure PortHatasi(const mesaj: UnicodeString);
    function PortuAc(const isim: string): Boolean;
    function AyarlamayiDene: Boolean;
    procedure PortuKapat;
    procedure KuyruguBosalt;
    procedure ModeliBosalt;
    procedure OturumBaslat;
    procedure OturumBitir(const d: TKartDurumu; rapor: Boolean);
    procedure DilimYazildi(const p: TPaket);
    procedure HataBildir(h, kaynak: Byte);
    procedure BaytIsle(b: Byte; t: Int64);
    procedure PaketKabul(const p: TPaket; t: Int64);
    procedure BilgiKabul(const p: TPaket; t: Int64);
    procedure Gozetle;
    function DurumPaketiAl(var p: TPaket; out uzunluk: Integer): Boolean;
    function KuyruktanAl(var p: TPaket; out nesil: DWord): Boolean;
    function PaketYaz(const p: TPaket; uzunluk: Integer; out hataKodu: DWord): Boolean;
    procedure YenidenDeneyerekYaz(var p: TPaket; uzunluk: Integer; nesil: DWord; dilimMi: Boolean);
    function GorulduMu: Boolean;
    function PortAdiniAl: UnicodeString;
  public
    constructor Create;
    destructor Destroy; override;

    procedure Kapat;
    procedure Hizmet;
    procedure KurulumuBaslat;
    procedure KurulumuSifirla(h: Byte);
    procedure CikislariAyarla(mil, cikis: Byte);
    function HataAl(out h, kaynak: Byte): Boolean;
    function DurusAl(out fark: TEksenTam; out belirsiz: Boolean): Boolean;
    function HareketeHazir: Boolean;
    function DilimGonder(x, y, z: Integer): Boolean;
    procedure Bosalt(zamanAsimiMs: DWord);
    function Derinlik: Integer;
    function DurumAl(out d: TKartDurumu): DWord;
    function BilgiAl(out bilgi: TKartSinirlari): DWord;
    procedure OkumaDongusu;
    procedure BekleyenOkumayiIptalEt;
    procedure YazmaDongusu;

    property Bagli: Boolean read FBagli;
    property Goruldu: Boolean read GorulduMu;
    property PortAdi: UnicodeString read PortAdiniAl;
    property YeniPortSayisi: DWord read FYeniPortNo;
    property SonHata: UnicodeString read FSonHata;
  end;

implementation

var
  gKisitlamaKalkti: Boolean = False;

{ ================= TBaglantiIsParcacigi ================= }

constructor TBaglantiIsParcacigi.Create(ASahip: TSeriBaglanti; AOkuyucu: Boolean);
begin
  FSahip := ASahip;
  FOkuyucu := AOkuyucu;
  inherited Create(True);
  FreeOnTerminate := False;
end;

procedure TBaglantiIsParcacigi.Execute;
begin
  while not FSahip.FIsDur do
  begin
    try
      if FOkuyucu then
        FSahip.OkumaDongusu
      else
        FSahip.YazmaDongusu;
    except
    end;
  end;
  if FOkuyucu then
  begin
    try
      FSahip.BekleyenOkumayiIptalEt;
    except
    end;
  end;
end;

{ ================= Yardımcılar ================= }

{ Windows'tan bu işlemi yavaşlatmamasını ister (güç kısıtlaması paketleri geciktirir). }
procedure GucKisitlamasiniKaldir;
var
  st: TPowerThrottling_;
begin
  if gKisitlamaKalkti then Exit;
  gKisitlamaKalkti := True;
  try
    st.Version := 1;
    st.ControlMask := 1 or 4;
    st.StateMask := 0;
    SetProcessInformation_(GetCurrentProcess, PROCESS_POWER_THROTTLING_, @st, SizeOf(st));
  except
  end;
end;

{ USB seri sürücüleri (Arduino USBSER, CH340, CP210x, PL2303, FTDI VCP, ...) }
function UsbSeriMi(const kayitYolu: string): Boolean;
begin
  Result := (Pos('USBSER', kayitYolu) > 0) or (Pos('VCP', kayitYolu) > 0) or (Pos('CH34', kayitYolu) > 0) or
    (Pos('WCH', kayitYolu) > 0) or (Pos('SILAB', kayitYolu) > 0) or (Pos('CP210', kayitYolu) > 0) or
    (Pos('PROLIFIC', kayitYolu) > 0) or (Pos('PL2303', kayitYolu) > 0) or (Pos('USB', kayitYolu) > 0);
end;

{ COM portlarını kayıt defterinden listeler (HARDWARE\DEVICEMAP\SERIALCOMM).
  USB seri portlar önce gelir. }
procedure ComPortlariniListele(l: TStringList);
var
  r: TRegistry;
  isimler, usb, diger: TStringList;
  i: Integer;
  anahtar, veri, kayitYolu, s: string;
begin
  l.Clear;
  r := TRegistry.Create(KEY_READ);
  isimler := TStringList.Create;
  usb := TStringList.Create;
  diger := TStringList.Create;
  usb.CaseSensitive := True;
  diger.CaseSensitive := True;
  try
    try
      r.RootKey := HKEY_LOCAL_MACHINE;
      if not r.OpenKeyReadOnly('HARDWARE\DEVICEMAP\SERIALCOMM') then Exit;
      r.GetValueNames(isimler);
      for i := 0 to isimler.Count - 1 do
      begin
        if i >= 256 then Break;
        anahtar := isimler[i];
        if r.GetDataType(anahtar) <> rdString then Continue;
        veri := r.ReadString(anahtar);
        if veri = '' then Continue;
        kayitYolu := UpperCase(anahtar);
        s := UpperCase(Trim(veri));
        if Copy(s, 1, 3) <> 'COM' then Continue;
        if Pos('BTH', kayitYolu) > 0 then Continue;
        if (usb.IndexOf(s) >= 0) or (diger.IndexOf(s) >= 0) then Continue;
        if UsbSeriMi(kayitYolu) then usb.Add(s) else diger.Add(s);
      end;
      l.AddStrings(usb);
      l.AddStrings(diger);
    except
    end;
  finally
    diger.Free;
    usb.Free;
    isimler.Free;
    r.Free;
  end;
end;

function YeniListe: TStringList;
begin
  Result := TStringList.Create;
  Result.CaseSensitive := True;
end;

{ ================= TSeriBaglanti ================= }

constructor TSeriBaglanti.Create;
var
  f: Int64;
begin
  inherited Create;
  InitCriticalSection(FKilit);
  FTutamac := INVALID_HANDLE_VALUE;
  FUyandir := api_CreateEventW(nil, False, False, nil);
  FillChar(FOkumaOv, SizeOf(FOkumaOv), 0);
  FillChar(FYazmaOv, SizeOf(FYazmaOv), 0);
  f := 0;
  FHassasSayac := api_QueryPerformanceFrequency(f);
  FHassasSayac := FHassasSayac and (f >= 1000);
  if FHassasSayac then
  begin
    FDilim := f div 200;
    FMsBasina := f div 1000;
  end
  else
  begin
    FDilim := 5;
    FMsBasina := 1;
  end;
  FModelZaman := SayacSimdi;
  FGidenKomut := K_SIFIRLA;
  FGidenKod := H_ACILIS;
  FBilgi := VarsayilanBilgi;
end;

destructor TSeriBaglanti.Destroy;
begin
  PortuKapat;
  if FUyandir <> 0 then
  begin
    CloseHandle(FUyandir);
    FUyandir := 0;
  end;
  FreeAndNil(FPortListesi);
  DoneCriticalSection(FKilit);
  inherited Destroy;
end;

procedure TSeriBaglanti.Kilitle; inline;
begin
  EnterCriticalSection(FKilit);
end;

procedure TSeriBaglanti.KilidiAc; inline;
begin
  LeaveCriticalSection(FKilit);
end;

function TSeriBaglanti.GorulduMu: Boolean;
begin
  Kilitle;
  try
    Result := FGoruldu and FBagli;
  finally
    KilidiAc;
  end;
end;

function TSeriBaglanti.PortAdiniAl: UnicodeString;
begin
  Result := UnicodeString(FPortAdi);
end;

function TSeriBaglanti.SayacSimdi: Int64;
var
  v: Int64;
begin
  if FHassasSayac then
  begin
    v := 0;
    api_QueryPerformanceCounter(v);
    Result := v;
  end
  else
    Result := Int64(SaatMs64);
end;

function TSeriBaglanti.SimdiMs: Int64;
begin
  Result := SayacSimdi div FMsBasina;
end;

{ Denenecek portların listesi: önce son kullanılan port, sonra diğerleri. }
function TSeriBaglanti.AdaylariOlustur: TStringList;
var
  l: TStringList;
  i: Integer;
begin
  Result := YeniListe;
  l := YeniListe;
  try
    ComPortlariniListele(l);
    PortListesiniIzle(l);
    if FTercihYok and (FTercih <> '') and (l.IndexOf(FTercih) >= 0) then
    begin
      FTazeDeneme := SER_TAZE_DENEME;
      FTazeZaman := SaatMs64;
    end;
    FTercihYok := (FTercih <> '') and (l.IndexOf(FTercih) < 0);
    if (not FTercihYok) and (FTercih <> '') then Result.Add(FTercih);
    for i := 0 to l.Count - 1 do
      if Result.IndexOf(l[i]) < 0 then Result.Add(l[i]);
  finally
    l.Free;
  end;
end;

{ Yeni takılan USB seri portları algılar. }
procedure TSeriBaglanti.PortListesiniIzle(l: TStringList);
var
  i: Integer;
begin
  if FPortListesi = nil then
  begin
    FPortListesi := YeniListe;
    FPortListesi.AddStrings(l);
    Exit;
  end;
  for i := 0 to l.Count - 1 do
    if FPortListesi.IndexOf(l[i]) < 0 then
      Inc(FYeniPortNo);
  FPortListesi.Clear;
  FPortListesi.AddStrings(l);
end;

function TSeriBaglanti.TercihListede: Boolean;
var
  l: TStringList;
begin
  Result := False;
  if FTercih = '' then Exit;
  l := YeniListe;
  try
    ComPortlariniListele(l);
    Result := l.IndexOf(FTercih) >= 0;
  finally
    l.Free;
  end;
end;

procedure TSeriBaglanti.PortHatasi(const mesaj: UnicodeString);
begin
  Kilitle;
  try
    HataBildir(H_ZAMANASIMI, HK_PC);
  finally
    KilidiAc;
  end;
  FSonHata := mesaj;
  FBagli := False;
end;

{ COM portunu çakışmalı (asenkron) G/Ç için açar. }
function TSeriBaglanti.PortuAc(const isim: string): Boolean;
var
  yol: AnsiString;
begin
  PortuKapat;
  FPortAdi := isim;
  yol := AnsiString('\\.\' + isim);
  FTutamac := api_CreateFileA(PAnsiChar(yol), GENERIC_READ or GENERIC_WRITE, 0, nil,
    OPEN_EXISTING, FILE_FLAG_OVERLAPPED, 0);
  if FTutamac = INVALID_HANDLE_VALUE then
  begin
    FSonHata := SerPortAcilamadi + UnicodeString(isim);
    Exit(False);
  end;
  api_EscapeCommFunction(FTutamac, CLRDTR_);
  api_EscapeCommFunction(FTutamac, CLRRTS_);
  FAyarBekliyor := True;
  FAyarBaslangic := SaatMs64;
  FAyarDeneme := 0;
  AyarlamayiDene;
  Result := True;
end;

{ 115200 baud, 8N1, akış denetimi yok ve zaman aşımlarını ayarlar.
  Bazı USB sürücüleri port göründükten sonra zaman istediği için yeniden denenir. }
function TSeriBaglanti.AyarlamayiDene: Boolean;
var
  dcb: TDCB_;
  sureler: TCommTimeouts_;
begin
  Result := False;
  if (not FAyarBekliyor) or (FTutamac = INVALID_HANDLE_VALUE) then Exit;
  Inc(FAyarDeneme);
  api_SetupComm(FTutamac, 4096, 4096);
  FillChar(dcb, SizeOf(dcb), 0);
  dcb.DCBlength := SizeOf(TDCB_);
  if not api_GetCommState(FTutamac, @dcb) then
  begin
    FSonHata := SerGetCommState + UnicodeString(FPortAdi);
    Exit;
  end;
  dcb.BaudRate := UNO_BAUD;
  dcb.ByteSize := 8;
  dcb.Parity := 0;
  dcb.StopBits := 0;
  dcb.Flags := 1;
  if not api_SetCommState(FTutamac, @dcb) then
  begin
    FSonHata := SerSetCommState + UnicodeString(FPortAdi);
    Exit;
  end;
  FAyarBekliyor := False;
  api_EscapeCommFunction(FTutamac, CLRDTR_);
  api_EscapeCommFunction(FTutamac, CLRRTS_);
  sureler.ReadIntervalTimeout := $FFFFFFFF;
  sureler.ReadTotalTimeoutMultiplier := $FFFFFFFF;
  sureler.ReadTotalTimeoutConstant := 20;
  sureler.WriteTotalTimeoutMultiplier := 0;
  sureler.WriteTotalTimeoutConstant := 0;
  api_SetCommTimeouts(FTutamac, @sureler);
  api_PurgeComm(FTutamac, PURGE_ALL_);
  FillChar(FOkumaOv, SizeOf(FOkumaOv), 0);
  FillChar(FYazmaOv, SizeOf(FYazmaOv), 0);
  FOkumaOv.hEvent := api_CreateEventW(nil, True, False, nil);
  FYazmaOv.hEvent := api_CreateEventW(nil, True, False, nil);
  FOkumaBekliyor := False;
  FSonHata := '';
  Kilitle;
  try
    FAlmaAdet := 0;
    FBozukBayt := 0;
    FGoruldu := False;
    FAlmaZamani := SaatMs64;
    FAlmaMs := SimdiMs;
    FBas := 0;
    FAdet := 0;
    FModelDerinlik := 0;
    FYaziyor := False;
    Inc(FNesil);
    FGidenKomut := K_SIFIRLA;
    FGidenKod := H_ACILIS;
    FBaglantiIstegi := False;
    FKartSifirlamada := False;
    FSifirlamaOnay := False;
    FOturum := False;
    FDurumHemen := False;
    FSonDurumMs := 0;
    FAlmaEsit := False;
  finally
    KilidiAc;
  end;
  FAcilisZamani := SaatMs64;
  FDuruyor := False;
  FBagli := True;
  api_timeBeginPeriod(1);
  FZamanlayiciAcik := True;
  GucKisitlamasiniKaldir;
  FIsDur := False;
  FOkumaIsi := TBaglantiIsParcacigi.Create(Self, True);
  FOkumaIsi.Priority := tpHigher;
  FYazmaIsi := TBaglantiIsParcacigi.Create(Self, False);
  FYazmaIsi.Priority := tpHigher;
  FOkumaIsi.Start;
  FYazmaIsi.Start;
  Result := True;
end;

procedure TSeriBaglanti.PortuKapat;
begin
  FDuruyor := True;
  if (FYazmaIsi <> nil) or (FOkumaIsi <> nil) then
  begin
    FIsDur := True;
    SetEvent(FUyandir);
    if FYazmaIsi <> nil then
    begin
      FYazmaIsi.WaitFor;
      FreeAndNil(FYazmaIsi);
    end;
    if FOkumaIsi <> nil then
    begin
      FOkumaIsi.WaitFor;
      FreeAndNil(FOkumaIsi);
    end;
  end;
  if FZamanlayiciAcik then
  begin
    api_timeEndPeriod(1);
    FZamanlayiciAcik := False;
  end;
  FBagli := False;
  FAyarBekliyor := False;
  if FTutamac <> INVALID_HANDLE_VALUE then
  begin
    api_CancelIo(FTutamac);
    CloseHandle(FTutamac);
    FTutamac := INVALID_HANDLE_VALUE;
  end;
  if FOkumaOv.hEvent <> 0 then CloseHandle(FOkumaOv.hEvent);
  if FYazmaOv.hEvent <> 0 then CloseHandle(FYazmaOv.hEvent);
  FOkumaOv.hEvent := 0;
  FYazmaOv.hEvent := 0;
  FOkumaBekliyor := False;
  Kilitle;
  try
    FGoruldu := False;
    OturumBitir(BosDurum, False);
    KuyruguBosalt;
    FGidenKomut := K_SIFIRLA;
    FBaglantiIstegi := False;
  finally
    KilidiAc;
  end;
end;

procedure TSeriBaglanti.Kapat;
begin
  PortuKapat;
end;

{ Her güncelleme döngüsünde çağrılır: port açar / arar, zaman aşımlarını denetler,
  kart yanıt vermeyince portu kapatır. }
procedure TSeriBaglanti.Hizmet;
var
  t, alma: QWord;
  gorulduSimdi: Boolean;
  l: TStringList;
  aday: string;
begin
  t := SaatMs64;
  if FAyarBekliyor then
  begin
    if AyarlamayiDene then Exit;
    if t - FAyarBaslangic < SER_AYAR_ZAMAN_ASIMI_MS then Exit;
    PortuKapat;
    if FPortAdi = FTercih then
    begin
      FAdaySira := 0;
      FTazeDeneme := SER_TAZE_DENEME;
      FTazeZaman := t;
    end;
    FSonDeneme := t;
    Exit;
  end;
  if FBagli then
  begin
    Kilitle;
    try
      gorulduSimdi := FGoruldu;
      alma := FAlmaZamani;
    finally
      KilidiAc;
    end;
    if gorulduSimdi then
    begin
      FGorulmustu := True;
      FTazeDeneme := 0;
      if FTercih <> FPortAdi then
      begin
        FTercih := FPortAdi;
        FAdaySira := 0;
      end;
      if (t > alma) and (t - alma > SER_ALMA_ZAMAN_ASIMI_MS) then PortHatasi(SerVeriYok);
    end
    else if t - FAcilisZamani > FAcilisBekleme then
      PortHatasi(SerKartYanitYok + UnicodeString(FPortAdi))
    else if FTercihYok and TercihListede then
    begin
      FBagli := False;
      FSonDeneme := 0;
      FAdaySira := 0;
      FTercihHata := 0;
      FTazeDeneme := SER_TAZE_DENEME;
      FTazeZaman := t;
    end;
  end;
  if FBagli then Exit;
  if (FTutamac <> INVALID_HANDLE_VALUE) or (FOkumaIsi <> nil) or (FYazmaIsi <> nil) then
  begin
    PortuKapat;
    FSonDeneme := 0;
  end;
  if (FSonDeneme <> 0) and (t - FSonDeneme < SER_YENIDEN_ACMA_MS) then Exit;
  FSonDeneme := t;
  l := AdaylariOlustur;
  try
    if l.Count = 0 then
    begin
      FSonHata := SerPortYok;
      Exit;
    end;
    if FGorulmustu then
    begin
      FGorulmustu := False;
      FAdaySira := 0;
    end;
    aday := l[FAdaySira mod l.Count];
  finally
    l.Free;
  end;
  if (aday = FTercih) and (FTazeDeneme = SER_TAZE_DENEME) and (FTazeZaman <> 0) and
     (t - FTazeZaman < SER_TAZE_BEKLEME_MS) then Exit;
  if (aday = FTercih) and (FTazeDeneme > 0) then
  begin
    FAcilisBekleme := SER_ACILIS_BEKLEME_TAZE_MS;
    Dec(FTazeDeneme);
  end
  else if aday = FTercih then
    FAcilisBekleme := SER_ACILIS_BEKLEME_KART_MS
  else
    FAcilisBekleme := SER_ACILIS_BEKLEME_MS;
  if PortuAc(aday) then
  begin
    FTercihHata := 0;
    Inc(FAdaySira);
  end
  else if (aday = FTercih) and (FTercihHata < SER_TERCIH_DENEME) then
  begin
    Inc(FTercihHata);
    FTazeDeneme := SER_TAZE_DENEME;
    FTazeZaman := t;
  end
  else
  begin
    FTercihHata := 0;
    Inc(FAdaySira);
  end;
end;

procedure TSeriBaglanti.KuyruguBosalt;
begin
  FBas := 0;
  FAdet := 0;
  FModelDerinlik := 0;
  Inc(FNesil);
end;

{ Kart tamponunda kaç dilim kaldığını tahmin eder (dilim başına 5 ms). }
procedure TSeriBaglanti.ModeliBosalt;
var
  anlik, dilimAdet: Int64;
begin
  anlik := SayacSimdi;
  if FModelDerinlik <= 0 then
  begin
    FModelDerinlik := 0;
    FModelZaman := anlik;
    Exit;
  end;
  dilimAdet := (anlik - FModelZaman) div FDilim;
  if dilimAdet <= 0 then Exit;
  if dilimAdet >= FModelDerinlik then
  begin
    FModelDerinlik := 0;
    FModelZaman := anlik;
  end
  else
  begin
    Dec(FModelDerinlik, Integer(dilimAdet));
    FModelZaman := FModelZaman + dilimAdet * FDilim;
  end;
end;

{ Hareket oturumu başlatır: durma konumunu hesaplamak için geçmişi temizler. }
procedure TSeriBaglanti.OturumBaslat;
var
  i: Integer;
begin
  FOturum := True;
  FOturumKart := False;
  FOturumKod := $FF;
  FYazilan := 0;
  FSonDilimMs := 0;
  for i := 0 to UNO_EKSEN - 1 do
  begin
    FYazilanToplam[i] := 0;
    FKabulToplam[i] := 0;
  end;
end;

{ Kart durunca oturumu bitirir: kartın bildirdiği durma dilimine göre her eksende
  gerçekte kaç adım yürütüldüğünü hesaplar. }
procedure TSeriBaglanti.OturumBitir(const d: TKartDurumu; rapor: Boolean);
var
  s, f, l, k: Int64;
  gecerli: Boolean;
  yurutulen: array[0..UNO_EKSEN - 1] of Int64;
  i: Integer;
begin
  if not FOturum then Exit;
  FOturum := False;
  if not FOturumKart then Exit;
  s := FYazilan;
  f := 0;
  gecerli := rapor and (d.AltAdim < AltAdimOlcegi) and
    ((d.Hata <> H_ACILIS) or (FOturumKod = H_ACILIS));
  if gecerli then
  begin
    l := s - ((s - d.DilimSayisi) and $FFFF);
    f := l;
    if d.AltAdim > 0 then Dec(f);
    gecerli := (f >= 0) and (s - f <= SER_GECMIS);
  end;
  for i := 0 to UNO_EKSEN - 1 do yurutulen[i] := FYazilanToplam[i];
  if gecerli then
  begin
    k := f;
    while k < s do
    begin
      for i := 0 to UNO_EKSEN - 1 do
        yurutulen[i] := yurutulen[i] - FGecmis[Integer(k mod SER_GECMIS), i];
      Inc(k);
    end;
    if d.AltAdim > 0 then
      for i := 0 to UNO_EKSEN - 1 do
        yurutulen[i] := yurutulen[i] + KismiAdim(FGecmis[Integer(f mod SER_GECMIS), i], d.AltAdim);
  end
  else if (FDurum.Durum = K_HAREKET) or (FDurum.Tampon > 0) or (FAdet > 0) or
          (SimdiMs - FSonDilimMs < SER_KURULUM_ZAMAN_ASIMI_MS) then
    FFarkBelirsiz := True;
  for i := 0 to UNO_EKSEN - 1 do
    FFark[i] := FFark[i] + FKabulToplam[i] - yurutulen[i];
  FFarkVar := True;
end;

procedure TSeriBaglanti.DilimYazildi(const p: TPaket);
var
  sira, i, v: Integer;
begin
  if not FOturum then Exit;
  sira := Integer(FYazilan mod SER_GECMIS);
  for i := 0 to UNO_EKSEN - 1 do
  begin
    v := PaketAdimlari(p, i);
    FGecmis[sira, i] := SmallInt(v);
    FYazilanToplam[i] := FYazilanToplam[i] + v;
  end;
  Inc(FYazilan);
  FSonDilimMs := SimdiMs;
end;

procedure TSeriBaglanti.HataBildir(h, kaynak: Byte);
begin
  if FGidenKomut = K_SIFIRLA then Exit;
  FGidenKomut := K_SIFIRLA;
  FBaglantiIstegi := False;
  if h > H_SON then h := H_ACILIS;
  FGidenKod := h;
  KuyruguBosalt;
  FHataKodu := h;
  FHataKaynagi := kaynak;
  Inc(FHataNo);
  FDurumHemen := True;
  SetEvent(FUyandir);
end;

{ Bir bayt alır ve paket kurar. Sağlama toplamı tutmazsa bir bayt kaydırıp
  yeniden dener; böylece gürültüden sonra bağlantı yeniden eşlenir. }
procedure TSeriBaglanti.BaytIsle(b: Byte; t: Int64);
var
  kalan, i: Integer;
  gecici: array of Byte;
begin
  if (FAlmaAdet > 0) and (t - FSonBaytMs > SER_BAYT_ARASI_MS) then
  begin
    FAlmaAdet := 0;
    Inc(FBozukBayt);
    HataBildir(H_UZUNLUK, HK_PC);
  end;
  FSonBaytMs := t;
  if (FAlmaAdet = 0) and (PaketUzunlugu(b, False) = 0) then
  begin
    Inc(FBozukBayt);
    HataBildir(H_KOMUT, HK_PC);
    Exit;
  end;
  FAlmaPenceresi[FAlmaAdet] := b;
  Inc(FAlmaAdet);
  if FAlmaAdet < UNO_DURUM_BOY then Exit;
  FAlinanPaket := FAlmaPenceresi;
  if SaglamaDogru(FAlinanPaket, UNO_DURUM_BOY) then
  begin
    FAlmaAdet := 0;
    PaketKabul(FAlinanPaket, t);
    Exit;
  end;
  Inc(FBozukBayt);
  HataBildir(H_SAGLAMA, HK_PC);
  kalan := FAlmaAdet - 1;
  SetLength(gecici, kalan);
  for i := 0 to kalan - 1 do gecici[i] := FAlmaPenceresi[i + 1];
  FAlmaAdet := 0;
  for i := 0 to kalan - 1 do BaytIsle(gecici[i], t);
end;

{ Geçerli bir durum paketini işler: sıra denetimi, kart sıfırlaması ve hatalar. }
procedure TSeriBaglanti.PaketKabul(const p: TPaket; t: Int64);
var
  d: TKartDurumu;
begin
  if p[0] = K_BILGI then
  begin
    BilgiKabul(p, t);
    Exit;
  end;
  if not PaketCoz(p, d) then Exit;
  if FAlmaEsit and (FGidenKomut <> K_SIFIRLA) and (d.Durum <> K_SIFIRLA) and (d.Sayac <> FAlmaNo) then
    HataBildir(H_SIRA, HK_PC);
  FAlmaNo := Byte(d.Sayac + 1);
  FAlmaEsit := True;
  FGoruldu := True;
  FAlmaZamani := SaatMs64;
  FAlmaMs := t;
  if d.Durum = K_SIFIRLA then
  begin
    if not FKartSifirlamada then
    begin
      FKartSifirlamada := True;
      FSifirlamaOnay := False;
      OturumBitir(d, True);
      HataBildir(d.Hata, HK_KART);
    end
    else if (FGidenKomut <> K_SIFIRLA) and (t - FKurulumMs > SER_KURULUM_TOLERANS_MS) then
      HataBildir(d.Hata, HK_KART);
  end
  else
  begin
    FKartSifirlamada := False;
    FSifirlamaOnay := False;
    if FOturum then FOturumKart := True;
  end;
  FDurum := d;
  Inc(FDurumNo);
  if d.Durum = K_SIFIRLA then
    FModelDerinlik := FAdet
  else
    FModelDerinlik := d.Tampon + FAdet;
  FModelZaman := SayacSimdi;
end;

{ Karttan K_BILGI: kartın hız sınırı. Kart bunu yalnızca SIFIRLA durumundayken
  gönderir (açılış, bağlantı zaman aşımı, bağlantının ilk K_SIFIRLA paketi);
  bu yüzden sıra sayacı izlenir ama denetlenmez, SIFIRLA durum paketi gibi. }
procedure TSeriBaglanti.BilgiKabul(const p: TPaket; t: Int64);
var
  bilgi: TKartSinirlari;
begin
  if not BilgiCoz(p, bilgi) then
  begin
    Inc(FBozukBayt);
    Exit;
  end;
  FAlmaNo := Byte(p[1] + 1);
  FAlmaEsit := True;
  FGoruldu := True;
  FAlmaZamani := SaatMs64;
  FAlmaMs := t;
  FBilgi := bilgi;
  Inc(FBilgiNo);
end;

{ Bağlantı bekçisi: eksik paketler ve 200 ms alma zaman aşımı. }
procedure TSeriBaglanti.Gozetle;
var
  t: Int64;
begin
  t := SimdiMs;
  Kilitle;
  try
    if (FAlmaAdet > 0) and (t - FSonBaytMs > SER_BAYT_ARASI_MS) then
    begin
      FAlmaAdet := 0;
      Inc(FBozukBayt);
      HataBildir(H_UZUNLUK, HK_PC);
    end;
    if (FGidenKomut <> K_SIFIRLA) and (t - FAlmaMs > SER_KURULUM_ZAMAN_ASIMI_MS) then
      HataBildir(H_ZAMANASIMI, HK_PC);
  finally
    KilidiAc;
  end;
end;

procedure TSeriBaglanti.KurulumuBaslat;
begin
  Kilitle;
  try
    FBaglantiIstegi := True;
    if FGidenKomut = K_SIFIRLA then FDurumHemen := True;
  finally
    KilidiAc;
  end;
  SetEvent(FUyandir);
end;

procedure TSeriBaglanti.KurulumuSifirla(h: Byte);
begin
  Kilitle;
  try
    FBaglantiIstegi := False;
    KuyruguBosalt;
    if FGidenKomut <> K_SIFIRLA then
    begin
      FGidenKomut := K_SIFIRLA;
      if h > H_SON then h := H_ACILIS;
      FGidenKod := h;
      FDurumHemen := True;
    end;
  finally
    KilidiAc;
  end;
  SetEvent(FUyandir);
end;

procedure TSeriBaglanti.CikislariAyarla(mil, cikis: Byte);
var
  degisti: Boolean;
begin
  cikis := cikis and C_MASKE;
  Kilitle;
  try
    degisti := (mil <> FGidenMil) or (cikis <> FGidenBit);
    if degisti then
    begin
      FGidenMil := mil;
      FGidenBit := cikis;
      if FGidenKomut <> K_SIFIRLA then FDurumHemen := True;
    end;
  finally
    KilidiAc;
  end;
  if degisti then SetEvent(FUyandir);
end;

function TSeriBaglanti.HataAl(out h, kaynak: Byte): Boolean;
begin
  Kilitle;
  try
    Result := FHataNo <> FHataAlinan;
    h := FHataKodu;
    kaynak := FHataKaynagi;
    FHataAlinan := FHataNo;
  finally
    KilidiAc;
  end;
end;

function TSeriBaglanti.DurusAl(out fark: TEksenTam; out belirsiz: Boolean): Boolean;
var
  i: Integer;
begin
  Kilitle;
  try
    Result := FFarkVar;
    belirsiz := FFarkBelirsiz;
    for i := 0 to UNO_EKSEN - 1 do
    begin
      fark[i] := LongInt(FFark[i]);
      FFark[i] := 0;
    end;
    FFarkVar := False;
    FFarkBelirsiz := False;
  finally
    KilidiAc;
  end;
end;

function TSeriBaglanti.HareketeHazir: Boolean;
begin
  Kilitle;
  try
    Result := FBagli and (FGidenKomut = K_KURULU) and FOturumKart and
      ((FDurum.Durum = K_KURULU) or (FDurum.Durum = K_HAREKET));
  finally
    KilidiAc;
  end;
end;

{ Bir hareket paketini kuyruğa koyar (sonraki 5 ms için X, Y, Z adımları). }
function TSeriBaglanti.DilimGonder(x, y, z: Integer): Boolean;
var
  sira, i: Integer;
begin
  Result := False;
  if not FBagli then Exit;
  Kilitle;
  try
    if (FGidenKomut <> K_KURULU) or (not FOturumKart) then Exit;
    if FAdet >= SER_KUYRUK_BOYU then Exit;
    sira := (FBas + FAdet) mod SER_KUYRUK_BOYU;
    HareketPaketi(FKuyruk[sira], x, y, z);
    for i := 0 to UNO_EKSEN - 1 do
      FKabulToplam[i] := FKabulToplam[i] + PaketAdimlari(FKuyruk[sira], i);
    Inc(FAdet);
    ModeliBosalt;
    Inc(FModelDerinlik);
  finally
    KilidiAc;
  end;
  SetEvent(FUyandir);
  Result := True;
end;

procedure TSeriBaglanti.Bosalt(zamanAsimiMs: DWord);
var
  t: QWord;
  mesgul: Boolean;
begin
  t := SaatMs64;
  repeat
    Kilitle;
    try
      mesgul := (FAdet > 0) or FYaziyor or (FDurumHemen and FGoruldu);
    finally
      KilidiAc;
    end;
    if (not mesgul) or (not FBagli) then Exit;
    Sleep(2);
  until SaatMs64 - t >= zamanAsimiMs;
end;

function TSeriBaglanti.Derinlik: Integer;
begin
  Kilitle;
  try
    ModeliBosalt;
    Result := FModelDerinlik;
  finally
    KilidiAc;
  end;
end;

function TSeriBaglanti.DurumAl(out d: TKartDurumu): DWord;
begin
  Kilitle;
  try
    d := FDurum;
    Result := FDurumNo;
  finally
    KilidiAc;
  end;
end;

{ Kullanılan kart sınırları (K_BILGI gelene kadar varsayılanlar). Yeni sınırlar
  her kaydedildiğinde sonuç değişir; çağıran böylece uygulaması gerektiğini anlar. }
function TSeriBaglanti.BilgiAl(out bilgi: TKartSinirlari): DWord;
begin
  Kilitle;
  try
    bilgi := FBilgi;
    Result := FBilgiNo;
  finally
    KilidiAc;
  end;
end;

{ O ana kadar gelen tüm baytları okur (çakışmalı ReadFile). }
procedure TSeriBaglanti.OkumaDongusu;
var
  bitti: Boolean;
  n, hataKodu, beklemeSonucu: DWord;
  t: Int64;
  i: Integer;
begin
  if (not FBagli) or (FTutamac = INVALID_HANDLE_VALUE) then
  begin
    Sleep(10);
    Exit;
  end;
  bitti := False;
  n := 0;
  if not FOkumaBekliyor then
  begin
    ResetEvent(FOkumaOv.hEvent);
    if api_ReadFile(FTutamac, @FOkumaTamponu[0], OKUMA_TAMPON_BOYU, nil, @FOkumaOv) then
    begin
      if api_GetOverlappedResult(FTutamac, @FOkumaOv, n, False) then
        bitti := True
      else
      begin
        PortHatasi(SerOkumaHatasi + UnicodeString(IntToStr(GetLastError)));
        Exit;
      end;
    end
    else
    begin
      hataKodu := GetLastError;
      if hataKodu = ERROR_IO_PENDING_ then
        FOkumaBekliyor := True
      else
      begin
        PortHatasi(SerOkumaHatasi + UnicodeString(IntToStr(hataKodu)));
        Exit;
      end;
    end;
  end;
  if FOkumaBekliyor then
  begin
    beklemeSonucu := WaitForSingleObject(FOkumaOv.hEvent, SER_OKUMA_ZAMAN_ASIMI_MS);
    if beklemeSonucu = WAIT_OBJECT_0_ then
    begin
      FOkumaBekliyor := False;
      n := 0;
      if api_GetOverlappedResult(FTutamac, @FOkumaOv, n, False) then
        bitti := True
      else
      begin
        PortHatasi(SerOkumaHatasi + UnicodeString(IntToStr(GetLastError)));
        Exit;
      end;
    end
    else if beklemeSonucu <> WAIT_TIMEOUT_ then
    begin
      PortHatasi(SerOkumaBeklemeHatasi + UnicodeString(IntToStr(GetLastError)));
      Exit;
    end;
  end;
  if bitti and (n > 0) then
  begin
    t := SimdiMs;
    Kilitle;
    try
      for i := 0 to Integer(n) - 1 do BaytIsle(FOkumaTamponu[i], t);
    finally
      KilidiAc;
    end;
  end;
end;

procedure TSeriBaglanti.BekleyenOkumayiIptalEt;
var
  n: DWord;
begin
  if FOkumaBekliyor and (FTutamac <> INVALID_HANDLE_VALUE) then
  begin
    api_CancelIo(FTutamac);
    n := 0;
    api_GetOverlappedResult(FTutamac, @FOkumaOv, n, True);
  end;
  FOkumaBekliyor := False;
end;

function TSeriBaglanti.DurumPaketiAl(var p: TPaket; out uzunluk: Integer): Boolean;
var
  t: Int64;
begin
  Result := False;
  uzunluk := UNO_DURUM_BOY;
  t := SimdiMs;
  Kilitle;
  try
    if not FGoruldu then Exit;
    if (FGidenKomut = K_SIFIRLA) and FBaglantiIstegi and FSifirlamaOnay then
    begin
      FGidenKomut := K_KURULU;
      FGidenKod := H_ACILIS;
      FSifirlamaOnay := False;
      FKurulumMs := t;
      FAlmaMs := t;
      FDurumHemen := True;
      OturumBaslat;
    end;
    if (not FDurumHemen) and (t - FSonDurumMs < SER_DURUM_MS) then Exit;
    FDurumHemen := False;
    FSonDurumMs := t;
    DurumPaketi(p, FGidenKomut, FGidenKod, FGidenMil, FGidenBit);
    if FGidenKomut = K_SIFIRLA then
    begin
      if FOturum and (FOturumKod = $FF) then FOturumKod := FGidenKod;
      if FKartSifirlamada and (not FSifirlamaOnay) then
      begin
        FSifirlamaOnay := True;
        if FBaglantiIstegi then FDurumHemen := True;
      end;
    end;
    FYaziyor := True;
    Result := True;
  finally
    KilidiAc;
  end;
end;

function TSeriBaglanti.KuyruktanAl(var p: TPaket; out nesil: DWord): Boolean;
begin
  Result := False;
  Kilitle;
  try
    nesil := FNesil;
    if FAdet <= 0 then Exit;
    p := FKuyruk[FBas];
    FBas := (FBas + 1) mod SER_KUYRUK_BOYU;
    Dec(FAdet);
    FYaziyor := True;
    Result := True;
  finally
    KilidiAc;
  end;
end;

function TSeriBaglanti.PaketYaz(const p: TPaket; uzunluk: Integer; out hataKodu: DWord): Boolean;
var
  n: DWord;
begin
  Result := False;
  hataKodu := 0;
  Move(p[0], FYazmaTamponu[0], uzunluk);
  ResetEvent(FYazmaOv.hEvent);
  if api_WriteFile(FTutamac, @FYazmaTamponu[0], DWord(uzunluk), nil, @FYazmaOv) then Exit(True);
  hataKodu := GetLastError;
  if hataKodu = ERROR_IO_PENDING_ then
  begin
    n := 0;
    if WaitForSingleObject(FYazmaOv.hEvent, SER_YAZMA_ZAMAN_ASIMI_MS) = WAIT_OBJECT_0_ then
    begin
      if api_GetOverlappedResult(FTutamac, @FYazmaOv, n, False) then
      begin
        hataKodu := 0;
        Exit(True);
      end;
      hataKodu := GetLastError;
    end
    else
    begin
      api_CancelIo(FTutamac);
      if api_GetOverlappedResult(FTutamac, @FYazmaOv, n, True) then
      begin
        hataKodu := 0;
        Exit(True);
      end;
      hataKodu := WAIT_TIMEOUT_;
    end;
  end;
end;

{ Paketi yazar; hata bildirmeden önce kısa zaman aşımında yeniden dener. }
procedure TSeriBaglanti.YenidenDeneyerekYaz(var p: TPaket; uzunluk: Integer; nesil: DWord; dilimMi: Boolean);
var
  deneme: Integer;
  hataKodu: DWord;
begin
  Kilitle;
  try
    if dilimMi then
    begin
      if nesil <> FNesil then Exit;
      DilimYazildi(p);
    end;
    p[1] := FGidenNo;
    FGidenNo := Byte(FGidenNo + 1);
    SaglamaEkle(p, uzunluk);
  finally
    KilidiAc;
  end;
  for deneme := 1 to SER_YAZMA_DENEME do
  begin
    if FDuruyor or (not FBagli) then Exit;
    if PaketYaz(p, uzunluk, hataKodu) then Exit;
    if hataKodu <> WAIT_TIMEOUT_ then
    begin
      PortHatasi(SerYazmaHatasi + UnicodeString(IntToStr(hataKodu)));
      Exit;
    end;
  end;
  PortHatasi(SerYazmaZamanAsimi);
end;

procedure TSeriBaglanti.YazmaDongusu;
var
  yazildi: Boolean;
  uzunluk: Integer;
  nesil: DWord;
begin
  if (not FBagli) or (FTutamac = INVALID_HANDLE_VALUE) then
  begin
    Sleep(10);
    Exit;
  end;
  Gozetle;
  yazildi := False;
  try
    if DurumPaketiAl(FGidenPaket, uzunluk) then
    begin
      yazildi := True;
      YenidenDeneyerekYaz(FGidenPaket, uzunluk, 0, False);
    end
    else if KuyruktanAl(FGidenPaket, nesil) then
    begin
      yazildi := True;
      YenidenDeneyerekYaz(FGidenPaket, UNO_HAREKET_BOY, nesil, True);
    end;
  finally
    if yazildi then
    begin
      Kilitle;
      try
        FYaziyor := False;
      finally
        KilidiAc;
      end;
    end;
  end;
  if not yazildi then WaitForSingleObject(FUyandir, 2);
end;

end.
