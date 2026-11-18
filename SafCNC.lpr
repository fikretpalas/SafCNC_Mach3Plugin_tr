{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : SafCNC.lpr - eklenti giriş noktası ve Mach3'e dışa aktarılan işlevler
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  Bu eklenti SafCNC yazılımı yüklü bir Arduino Uno ya da Nano'yu Mach3 için
  USB hareket denetleyicisine çevirir. Mach3 yörüngeyi planlar; eklenti onu
  5 ms'lik dilimlere böler ve adım sayılarını USB seri (115200 baud) üzerinden
  karta gönderir. Kart bunları 32 kHz DDA zamanlayıcısıyla oynatır.

  DİĞER KARTLAR
    Eklenti yalnızca Arduino için değildir. Aynı paket protokolünü konuşan her
    kartla kullanılabilir. Arduino Uno / Nano yaklaşık 30 kHz üzerine çıkamaz;
    STM32 kart yaklaşık 100 kHz'e (5 ms'lik dilimde 500 adım) çıkabilir.
    STM32 tarafı henüz test edilmedi. Kart çalışma hızını açılışta eklentiye
    bildirir; Mach3'teki eksen hızları bunu aşıyorsa eklenti uyarır ve kart
    hızlar düşürülene kadar bağlanmaz.

  DERLEME
    Mach3 32 bit bir programdır; bu DLL i386-win32 hedefiyle derlenmelidir.
    64 bit derleme yüklenmez. Açılışta eklenti Mach3 veri yapısı düzenini de
    denetler; uymazsa kendini devre dışı bırakır.
      - Derleyici : Lazarus / Free Pascal 3.2.x, hedef i386-win32
      - Kurulum   : SafCNC.dll dosyasını Mach3\PlugIns klasörüne kopyalayın

  GÜVENLİK
    Her pakette sıra sayacı ve sağlama toplamı vardır. Bağlantı 200 ms sessiz
    kalırsa kart kendiliğinden durur. Limit, prob ve kartın kendi acil stop
    girişi PC'den bağımsız olarak kartta işlenir.
    Her zaman motor ve fener mili gücünü kesen donanımsal acil stop kullanın.
}
library SafCNC;

{$mode objfpc}{$H+}
{$codepage utf8}
{$R-}{$Q-}

{$IFNDEF CPU386}
  {$FATAL SafCNC.dll 32 bit (i386-win32) olarak derlenmelidir - Mach3 32 bit bir programdır.}
{$ENDIF}

uses
  Windows, SysUtils, Math,
  uSistemApi, uMesajlar, uKartProtokol, uAnaProgram, uSeriBaglanti,
  uKartPenceresi, uKartKatmani, uCihaz;

const
  ACILIS_MESAJ_GECIKME = 20;
  SIFIRLAMA_MESAJ_GECIKME = 3;
  { Pencere çerçevesine fare tıklamaları ve Windows kipli döngüsünü başlatan mesajlar }
  WM_NCLBUTTONDOWN_ = $00A1;
  WM_NCRBUTTONDOWN_ = $00A4;
  WM_NCMBUTTONDOWN_ = $00A7;
  WM_NCLBUTTONDBLCLK_ = $00A3;
  WM_NCRBUTTONDBLCLK_ = $00A6;
  WM_NCMBUTTONDBLCLK_ = $00A9;
  WM_ENTERMENULOOP_ = $0211;
  WM_ENTERSIZEMOVE_ = $0231;
  WM_EXITSIZEMOVE_ = $0232;
  WM_SIZING_ = $0214;
  WM_MOVING_ = $0216;

var
  gCihaz: TCihaz = nil;
  gEtkin: Boolean = False;
  gMenuKimlik: Integer = 0;
  gMenuTutamac: HMENU = 0;
  gMenuPencere: HWND = 0;
  gMenuAdayi: HWND = 0;
  gKancaPencere: HWND = 0;
  gEskiYordam: Pointer = nil;
  gKancaUnicode: Boolean = False;
  gTasimaDongusu: Boolean = False;
  gTasimaAlani: TRect;
  gEklentiAdiA: AnsiString = '';

{ ================= Menü ve pencere kancası ================= }

{ SafCNC kart durum penceresini açar. }
procedure DurumPenceresiniAc;
var
  m: UnicodeString;
begin
  try
    if gEtkin and (gCihaz <> nil) then gCihaz.PencereyiGoster(gMenuPencere);
  except
    on e: Exception do
    begin
      m := HataDurumPenceresi + UnicodeString(e.ClassName) + ': ' + UnicodeString(e.Message);
      api_MessageBoxW(0, PWideChar(m), PWideChar(EklentiAdi), MB_OK);
    end;
  end;
end;

{ Mach3 ana penceresindeki pencere yordamı kancası: menü öğemize tıklamayı yakalar
  ve jog'u pencere çerçevesine ya da menü çubuğuna yapılan tıklamalara karşı korur. }
function MenuKancasi(pencere: HWND; mesaj: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall;
var
  mesgul: Boolean;
begin
  if (mesaj = WM_COMMAND) and (gMenuKimlik <> 0) and (lp = 0) and
     ((LongInt(wp) and $FFFF) = (gMenuKimlik and $FFFF)) then
  begin
    DurumPenceresiniAc;
    Exit(0);
  end;
  { Başlık çubuğuna, çerçeveye ya da menü çubuğuna tıklanınca Windows Mach3
    penceresini bir süre bekletir (sürüklenirse pencere kayar); bu sırada jog
    dilimi üretilemez. Jog tuşu basılıyken ya da jog sürerken böyle bir tıklama
    jog'u yavaşlatarak durdurur ve Windows'a iletilmez: pencere kaymaz ve hiç
    beklemez. Klavyeyle başlatılan taşıma ve menü (Alt) burada iptal edilemez,
    yalnızca jog'u durdurur. }
  if (mesaj = WM_NCLBUTTONDOWN_) or (mesaj = WM_NCRBUTTONDOWN_) or (mesaj = WM_NCMBUTTONDOWN_) or
     (mesaj = WM_NCLBUTTONDBLCLK_) or (mesaj = WM_NCRBUTTONDBLCLK_) or (mesaj = WM_NCMBUTTONDBLCLK_) then
  begin
    mesgul := False;
    try
      if gEtkin and (gCihaz <> nil) then mesgul := gCihaz.PencereEtkilesimi;
    except
    end;
    if mesgul then Exit(0);
  end
  else if (mesaj = WM_ENTERMENULOOP_) or (mesaj = WM_ENTERSIZEMOVE_) then
  begin
    if mesaj = WM_ENTERSIZEMOVE_ then
    begin
      gTasimaDongusu := False;
      if api_GetWindowRect(pencere, @gTasimaAlani) then gTasimaDongusu := True;
    end;
    try
      if gEtkin and (gCihaz <> nil) then gCihaz.PencereEtkilesimi;
    except
    end;
  end
  else if mesaj = WM_EXITSIZEMOVE_ then
    gTasimaDongusu := False
  { Pencere fareyle taşınır ya da boyutlandırılırken bir tuşa basıldı. Windows
    pencereyi yön tuşlarıyla kaydırır ve jog taşıma döngüsünün içinden başlardı.
    Pencere eski yerine konur, taşıma iptal edilir ve tüm tuşlar bırakılana
    kadar jog kilitli kalır. }
  else if ((mesaj = WM_MOVING_) or (mesaj = WM_SIZING_)) and gTasimaDongusu and (lp <> 0) then
  begin
    mesgul := False;
    try
      if gEtkin and (gCihaz <> nil) then mesgul := gCihaz.TasimadaTusDenetle;
    except
    end;
    if mesgul then
    begin
      PRect(lp)^ := gTasimaAlani;
      gTasimaDongusu := False;
      api_ReleaseCapture;
      Exit(1);
    end;
  end;
  if gKancaUnicode then
    Result := api_CallWindowProcW(gEskiYordam, pencere, mesaj, wp, lp)
  else
    Result := api_CallWindowProcA(gEskiYordam, pencere, mesaj, wp, lp);
end;

{ Mach3 ana penceresini alt sınıflar; mesajları önce MenuKancasi alır. }
procedure KancaKur(pencere: HWND);
begin
  if (gKancaPencere <> 0) or (pencere = 0) then Exit;
  gKancaUnicode := IsWindowUnicode(pencere);
  if gKancaUnicode then
    gEskiYordam := Pointer(PtrInt(api_SetWindowLongW(pencere, GWL_WNDPROC_, LongInt(PtrInt(@MenuKancasi)))))
  else
    gEskiYordam := Pointer(PtrInt(api_SetWindowLongA(pencere, GWL_WNDPROC_, LongInt(PtrInt(@MenuKancasi)))));
  if gEskiYordam <> nil then gKancaPencere := pencere;
end;

{ Asıl pencere yordamını geri koyar (bizden sonra başkası kancalamadıysa). }
procedure KancaKaldir;
var
  simdiki: Pointer;
begin
  if gKancaPencere = 0 then Exit;
  if gKancaUnicode then
    simdiki := Pointer(PtrInt(api_GetWindowLongW(gKancaPencere, GWL_WNDPROC_)))
  else
    simdiki := Pointer(PtrInt(api_GetWindowLongA(gKancaPencere, GWL_WNDPROC_)));
  if simdiki = Pointer(@MenuKancasi) then
  begin
    if gKancaUnicode then
      api_SetWindowLongW(gKancaPencere, GWL_WNDPROC_, LongInt(PtrInt(gEskiYordam)))
    else
      api_SetWindowLongA(gKancaPencere, GWL_WNDPROC_, LongInt(PtrInt(gEskiYordam)));
  end;
  gKancaPencere := 0;
  gEskiYordam := nil;
end;

{ "PlugIn Control" menüsünün konumu; bulunamazsa -1. }
function EklentiMenuKonumu(menu: HMENU): Integer;
var
  n, i: Integer;
  arabellek: array[0..255] of AnsiChar;
  s: AnsiString;
begin
  Result := -1;
  n := GetMenuItemCount(menu);
  for i := 0 to n - 1 do
  begin
    FillChar(arabellek, SizeOf(arabellek), 0);
    if api_GetMenuStringA(menu, UINT(i), @arabellek[0], 255, MF_BYPOSITION_) > 0 then
    begin
      s := LowerCase(StringReplace(AnsiString(PAnsiChar(@arabellek[0])), '&', '', [rfReplaceAll]));
      if Pos('plugin', s) > 0 then Exit(i);
    end;
  end;
end;

{ EnumWindows geri çağrısı: menü çubuğu olan görünür Mach3 ana penceresini bulur. }
function AnaPencereyiBul(pencere: HWND; lp: LPARAM): BOOL; stdcall;
var
  pid: DWORD;
  menu: HMENU;
begin
  Result := True;
  try
    pid := 0;
    api_GetWindowThreadProcessId(pencere, @pid);
    if pid <> GetCurrentProcessId then Exit;
    if not IsWindowVisible(pencere) then Exit;
    menu := GetMenu(pencere);
    if menu = 0 then Exit;
    if gMenuAdayi = 0 then gMenuAdayi := pencere;
    if EklentiMenuKonumu(menu) >= 0 then
    begin
      gMenuPencere := pencere;
      Result := False;
    end;
  except
  end;
end;

{ SafCNC öğesini PlugIn Control menüsüne ekler (menü yoksa kendi menüsünü açar). }
procedure EklentiMenusuEkle;
var
  cubuk, altMenu: HMENU;
  konum: Integer;
  ad, anaAd: AnsiString;
begin
  if (gMenuKimlik <> 0) or (not Assigned(GetMenuRange)) then Exit;
  gMenuKimlik := GetMenuRange(1);
  if gMenuKimlik = 0 then Exit;
  gMenuPencere := 0;
  gMenuAdayi := 0;
  api_EnumWindows(@AnaPencereyiBul, 0);
  if gMenuPencere = 0 then gMenuPencere := gMenuAdayi;
  if gMenuPencere = 0 then Exit;
  cubuk := GetMenu(gMenuPencere);
  altMenu := 0;
  konum := EklentiMenuKonumu(cubuk);
  if konum >= 0 then altMenu := GetSubMenu(cubuk, konum);
  ad := AnsiString(MenuAdi);
  anaAd := AnsiString(AnaMenuAdi);
  if altMenu <> 0 then
  begin
    gMenuTutamac := altMenu;
    api_AppendMenuA(altMenu, MF_STRING_, UINT_PTR(gMenuKimlik), PAnsiChar(ad));
  end
  else
  begin
    gMenuTutamac := CreatePopupMenu;
    api_AppendMenuA(gMenuTutamac, MF_STRING_, UINT_PTR(gMenuKimlik), PAnsiChar(ad));
    api_AppendMenuA(cubuk, MF_POPUP_, UINT_PTR(gMenuTutamac), PAnsiChar(anaAd));
  end;
  DrawMenuBar(gMenuPencere);
  KancaKur(gMenuPencere);
end;

{ Eklenti dururken menü öğemizi ve pencere kancasını kaldırır. }
procedure EklentiMenusuKaldir;
begin
  KancaKaldir;
  if (gMenuKimlik <> 0) and (gMenuTutamac <> 0) then
  begin
    api_DeleteMenu(gMenuTutamac, UINT(gMenuKimlik), MF_BYCOMMAND_);
    if gMenuPencere <> 0 then DrawMenuBar(gMenuPencere);
  end;
  gMenuKimlik := 0;
  gMenuTutamac := 0;
end;

{ ================= Mach3'ün çağırdığı dışa aktarılan işlevler ================= }

{ Aşağıdaki Set... işlevleri Mach3 geri çağırma işaretçilerini
  (düğmeler, DRO'lar, LED'ler, G-kod) alıp saklar. }
procedure m3_SetGetMenuRange(islev: Pointer); cdecl;
begin
  GetMenuRange := TTamKisa(islev);
end;

procedure m3_SetDoButton(islev: Pointer); cdecl;
begin
  DoButton := TYordamKisa(islev);
end;

procedure m3_SetSetDRO(islev: Pointer); cdecl;
begin
  SetDRO := TYordamKisaReel(islev);
end;

procedure m3_SetGetDRO(islev: Pointer); cdecl;
begin
  GetDRO := TReelKisa(islev);
end;

procedure m3_SetGetLED(islev: Pointer); cdecl;
begin
  GetLED := TMantikKisa(islev);
end;

procedure m3_SetSetLED(islev: Pointer); cdecl;
begin
  SetLED := TYordamKisaMantik(islev);
end;

procedure m3_SetCode(islev: Pointer); cdecl;
begin
  Code := TYordamMetin(islev);
end;

{ Mach3 ilk bunu çağırır. Mach3 veri bloğu işaretçilerini saklar ve bellek
  düzeninin 32 bit derlemeye uyduğunu denetler. Uymazsa eklenti kapalı kalır. }
function m3_InitControl(oEngine, oAyar, oMainPlanner, oGorunum: Pointer): Boolean; cdecl;
var
  m: UnicodeString;
begin
  Result := True;
  try
    Engine := oEngine;
    AyarBlogu := oAyar;
    MainPlanner := oMainPlanner;
    GorunumBlogu := oGorunum;
    gEtkin := DuzenGecerli and (oEngine <> nil) and (oMainPlanner <> nil) and (oGorunum <> nil);
    if not gEtkin then
    begin
      m := EklentiAdi + ': ' + HataVeriYapisi;
      api_MessageBoxW(0, PWideChar(m), PWideChar(EklentiAdi), MB_OK);
      Exit;
    end;
    if gCihaz = nil then gCihaz := TCihaz.Create;
    gCihaz.DenetimiBaslat;
  except
    gEtkin := False;
  end;
end;

{ Etkin Mach3 profil adını alır ve eklenti adını döndürür. }
function m3_SetProName(isim: PAnsiChar): PAnsiChar; cdecl;
begin
  try
    if isim <> nil then ProfilAdi := AnsiString(isim) else ProfilAdi := '';
  except
  end;
  if gEklentiAdiA = '' then gEklentiAdiA := AnsiString(EklentiAdi);
  Result := PAnsiChar(gEklentiAdiA);
end;

{ Mach3 açılışını bitirince çağrılır: karta bağlanır ve menüyü ekler. }
procedure m3_PostInitControl; cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then
    begin
      DurumMesajiniErtele(ACILIS_MESAJ_GECIKME);
      gCihaz.AcilisSonrasi;
      EklentiMenusuEkle;
    end;
  except
  end;
end;

procedure m3_Config; cdecl;
begin
end;

{ Mach3 kapanırken çağrılır: kartı durdurur ve kaynakları bırakır. }
procedure m3_StopPlug; cdecl;
begin
  try
    if gCihaz <> nil then gCihaz.Sonlandir;
    EklentiMenusuKaldir;
    if gCihaz <> nil then gCihaz.PencereyiBirak;
  except
  end;
end;

{ Mach3 her güncelleme döngüsünde çağırır. Eklentinin ana hizmet döngüsü. }
procedure m3_Update; cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then
    begin
      gCihaz.Guncelle;
      gCihaz.PencereyiGuncelle;
      DurumMesajiHizmeti;
    end;
  except
  end;
end;

{ Mach3 menü bildirimi: öğemiz seçilince durum penceresini açar. }
procedure m3_Notify(kimlik: Integer); cdecl;
begin
  try
    if (gMenuKimlik <> 0) and (kimlik = gMenuKimlik) then DurumPenceresiniAc;
  except
  end;
end;

{ G4 bekleme komutu. }
procedure m3_DoDwell(sure: Double); cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then gCihaz.Bekle(sure);
  except
  end;
end;

{ Mach3 Reset düğmesine basıldı (acil stop'a girme ya da çıkma). }
procedure m3_Reset; cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then
    begin
      DurumMesajiniErtele(SIFIRLAMA_MESAJ_GECIKME);
      gCihaz.Sifirla;
    end;
  except
  end;
end;

{ Mach3'ten jog tuşu basma / bırakma, Purge, Probe ve Home istekleri. }
procedure m3_JogOn(eksen, yon: SmallInt; surat: Double); cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then gCihaz.JogBaslat(eksen, yon, surat);
  except
  end;
end;

procedure m3_JogOff(eksen: SmallInt); cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then gCihaz.JogBitir(eksen);
  except
  end;
end;

procedure m3_Purge(flags: SmallInt); cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then gCihaz.Temizle(flags);
  except
  end;
end;

procedure m3_Probe; cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then gCihaz.ProbIstegi;
  except
  end;
end;

procedure m3_Home(eksen: SmallInt); cdecl;
begin
  try
    if gEtkin and (gCihaz <> nil) then gCihaz.ReferansaGit(eksen);
  except
  end;
end;

exports
  m3_SetGetMenuRange name 'SetGetMenuRange',
  m3_SetDoButton name 'SetDoButton',
  m3_SetSetDRO name 'SetSetDRO',
  m3_SetGetDRO name 'SetGetDRO',
  m3_SetGetLED name 'SetGetLED',
  m3_SetSetLED name 'SetSetLED',
  m3_SetCode name 'SetCode',
  m3_InitControl name 'InitControl',
  m3_SetProName name 'SetProName',
  m3_PostInitControl name 'PostInitControl',
  m3_Config name 'Config',
  m3_StopPlug name 'StopPlug',
  m3_Update name 'Update',
  m3_Notify name 'Notify',
  m3_DoDwell name 'DoDwell',
  m3_Reset name 'Reset',
  m3_JogOn name 'JogOn',
  m3_JogOff name 'JogOff',
  m3_Purge name 'Purge',
  m3_Probe name 'Probe',
  m3_Home name 'Home';

begin
  { Mach3 (MSVC) kayan nokta istisnalarını maskeli çalışır. FPC çalışma zamanı
    DLL yüklenirken bunları açabilir; Mach3'ü bozmamak için hepsini maskeliyoruz.
    NaN / sonsuz değerler kodda IsNan / IsInfinite ile ayrıca denetleniyor. }
  SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide, exOverflow,
    exUnderflow, exPrecision]);
end.
