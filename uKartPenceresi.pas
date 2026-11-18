{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uKartPenceresi.pas - kart durum penceresi
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  PlugIn Control > SafCNC ile açılan pencere: bağlantı lambası, port ve
  baud hızı. Koyu temalı düz Win32 penceresi; LCL kullanılmaz.
  Aynı temayla eksen hızı uyarısı: Mach3'teki hızlar kartın sınırını aşınca
  açılır; Tamam ile kapanır.
}
unit uKartPenceresi;

{$mode objfpc}{$H+}
{$codepage utf8}
{$R-}{$Q-}

interface

uses
  Windows, SysUtils, Math, uSistemApi, uMesajlar, uAnaProgram;

type
  { Durum penceresinde gösterilen bilgiler }
  TKartBilgisi = record
    Kurulu: Boolean;
    Mevcut: Boolean;
    PortAdi: UnicodeString;
    Baud: DWord;
    GeriBildirimVar: Boolean;
    Lamba: Byte;
  end;

  TKartBilgisiFn = function: TKartBilgisi of object;

  TLambaModu = (lmBilinmiyor, lmYanSon1Hz, lmSabit, lmYanSon4Hz);

  TRgb = record
    R, G, B: Byte;
  end;

  { Kenarı yumuşatılmış yuvarlak durum lambası.
    Kart durumuna göre sabit, 1 Hz ya da 4 Hz yanıp söner. }
  TSanalLamba = class
  private
    FBoyut: Integer;
    FMod: TLambaModu;
    FYaniyor: Boolean;
    FSayac: Integer;
    FKirli: Boolean;
    FPikseller: array of DWord;
    procedure DurumuHesapla;
    procedure ModAyarla(yeniDeger: TLambaModu);
  public
    constructor Create(boyut: Integer);
    procedure Vurus;
    procedure KartKodunuUygula(kodDeger: Byte);
    function YenidenCizilmeli: Boolean;
    procedure Ciz(dc: HDC; x, y: Integer; zeminRengi: DWord);
    class function YananSimgeOlustur(boyut: Integer): HICON;
  end;

const
  LAMBA_VURUS_MS = 125;

procedure KartPenceresiGoster(sahip: HWND; bilgiAl: TKartBilgisiFn);
procedure KartPenceresiGuncelle;
procedure KartPenceresiSerbest;

{ Eksen hızı uyarısını açar (zaten açıksa bir şey yapmaz). Pencere kipli
  değildir ve her zaman üstte durur; Mach3 kendi döngüsünü sürdürür. }
procedure HizUyarisiGoster(const metin: UnicodeString);
function HizUyarisiAcik: Boolean;
procedure HizUyarisiKapat;

implementation

const
  PENCERE_SINIFI: UnicodeString = 'SafCNCCardWnd';
  YAZI_TIPI_ADI: UnicodeString = 'Segoe UI';
  SINIF_STATIK: UnicodeString = 'STATIC';
  RENK_YESIL = $007DD73C;
  RENK_TURUNCU = $000078C8;
  RENK_KIRMIZI = $005046EB;
  RENK_ZEMIN = $0016110F;
  RENK_YUZEY = $00231B18;
  RENK_KENAR = $004E3D36;
  RENK_YAZI = $00F0E6E0;
  RENK_VURGU = $00FFC800;
  KIMLIK_LAMBA = 130;
  KIMLIK_ZAMANLAYICI = 1;
  LAMBA_BOYU = 22;
  SS_OWNERDRAW_ = $0000000D;
  DT_SINGLELINE_ = $0020;
  DT_NOPREFIX_ = $0800;
  SATIR_SAYISI = 2;
  PANEL_SOL = 6;
  PANEL_EN = 360;
  PANEL_UST = 6;
  PANEL_YUK = 80;
  YENILEME_MS = 200;
  ALAN_EN = 372;
  ALAN_YUK = PANEL_UST + PANEL_YUK + 6;
  UYARI_SINIFI: UnicodeString = 'SafCNCSpeedWnd';
  SINIF_DUGME: UnicodeString = 'BUTTON';
  KIMLIK_TAMAM = 140;
  UYARI_EN = 480;
  UYARI_METIN_UST = 30;
  DUGME_EN = 120;
  DUGME_YUK = 30;
  BS_OWNERDRAW_ = $0000000B;
  ODT_BUTTON_ = 4;
  ODS_SELECTED_ = $0001;
  BN_CLICKED_ = 0;
  DT_CENTER_ = $0001;
  DT_VCENTER_ = $0004;
  DT_WORDBREAK_ = $0010;
  DT_CALCRECT_ = $0400;
  WS_EX_TOPMOST_ = $0008;
  SM_CXSCREEN_ = 0;
  SM_CYSCREEN_ = 1;
  MB_TOPMOST_ = $00040000;

var
  gFircaZemin: HBRUSH = 0;
  gFircaYuzey: HBRUSH = 0;
  gFircaKenar: HBRUSH = 0;
  gPencere: HWND = 0;
  gYaziNormal: HFONT = 0;
  gYaziKalin: HFONT = 0;
  gSinifHazir: Boolean = False;
  gEtiketler: array[0..SATIR_SAYISI - 1] of HWND;
  gLamba: TSanalLamba = nil;
  gLambaPencere: HWND = 0;
  gSimgeKucuk: HICON = 0;
  gSimgeBuyuk: HICON = 0;
  gGosterilen: array[0..SATIR_SAYISI - 1] of UnicodeString;
  gDurumRengi: DWord = RENK_KIRMIZI;
  gSonYenileme: QWord = 0;
  gBilgiAl: TKartBilgisiFn;
  gFircaVurgu: HBRUSH = 0;
  gUyari: HWND = 0;
  gUyariMetni: UnicodeString = '';
  gUyariMetinYuk: Integer = 0;
  gUyariSinifHazir: Boolean = False;

{ ================= TSanalLamba ================= }

function RenkRgb(r, g, b: Integer): TRgb;
begin
  Result.R := Byte(r);
  Result.G := Byte(g);
  Result.B := Byte(b);
end;

function Karistir(const c1, c2: TRgb; a: Double): TRgb;
begin
  if a <= 0 then Exit(c1);
  if a >= 1 then Exit(c2);
  Result := RenkRgb(
    Round(c1.R + (c2.R - c1.R) * a),
    Round(c1.G + (c2.G - c1.G) * a),
    Round(c1.B + (c2.B - c1.B) * a));
end;

function Sinirla01(v: Double): Double;
begin
  if v < 0 then Exit(0);
  if v > 1 then Exit(1);
  Result := v;
end;

{ Lambayı bir piksel tamponuna çizer (yumuşak kenar, parlama). }
procedure LambaCiz(var cikti: array of DWord; n: Integer; const anaRenk: TRgb;
  etkin: Boolean; const zeminRgb: TRgb; saydam: Boolean);
var
  beyaz, parlak, koyu, dolgu, c: TRgb;
  cx, cy, r, hx, hy, sx, sy, px, py, uzaklik, kaplama, hd, kenar, sd, sp: Double;
  ix, iy: Integer;
  a, v: DWord;
begin
  beyaz := RenkRgb(255, 255, 255);
  if etkin then parlak := Karistir(anaRenk, beyaz, 0.6)
  else parlak := Karistir(anaRenk, beyaz, 0.2);
  koyu := Karistir(anaRenk, RenkRgb(0, 0, 0), 0.6);
  cx := n / 2.0;
  cy := n / 2.0;
  r := n / 2.0 - 1.5;
  hx := cx - r * 0.3;
  hy := cy - r * 0.35;
  sx := cx - r * 0.35;
  sy := cy - r * 0.4;
  for iy := 0 to n - 1 do
    for ix := 0 to n - 1 do
    begin
      px := ix + 0.5;
      py := iy + 0.5;
      uzaklik := Sqrt(Sqr(px - cx) + Sqr(py - cy));
      kaplama := Sinirla01(r - uzaklik + 0.5);
      dolgu := zeminRgb;
      if kaplama > 0 then
      begin
        hd := Sqrt(Sqr(px - hx) + Sqr(py - hy)) / r;
        dolgu := Karistir(parlak, anaRenk, Sinirla01(hd * 1.3));
        kenar := Sinirla01((uzaklik - (r - 2.0)) / 2.0);
        dolgu := Karistir(dolgu, koyu, kenar * 0.85);
        if etkin then
        begin
          sd := Sqrt(Sqr(px - sx) + Sqr(py - sy));
          sp := Sinirla01(1.5 - sd / (r * 0.3));
          dolgu := Karistir(dolgu, beyaz, sp * 0.85);
        end;
      end;
      if saydam then
      begin
        a := DWord(Round(kaplama * 255));
        if a = 0 then v := 0
        else v := (a shl 24) or (DWord(dolgu.R) shl 16) or (DWord(dolgu.G) shl 8) or dolgu.B;
        cikti[iy * n + ix] := v;
      end
      else
      begin
        c := Karistir(zeminRgb, dolgu, kaplama);
        v := (DWord(c.R) shl 16) or (DWord(c.G) shl 8) or c.B;
        cikti[(n - 1 - iy) * n + ix] := v;
      end;
    end;
end;

constructor TSanalLamba.Create(boyut: Integer);
begin
  inherited Create;
  if boyut < 8 then boyut := 8;
  FBoyut := boyut;
  SetLength(FPikseller, FBoyut * FBoyut);
  FMod := lmBilinmiyor;
  FYaniyor := False;
  FSayac := 0;
  FKirli := True;
end;

procedure TSanalLamba.DurumuHesapla;
var
  lambaAcik: Boolean;
begin
  case FMod of
    lmSabit: lambaAcik := True;
    lmYanSon1Hz: lambaAcik := FSayac < 4;
    lmYanSon4Hz: lambaAcik := (FSayac mod 2) = 0;
  else
    lambaAcik := False;
  end;
  if lambaAcik <> FYaniyor then
  begin
    FYaniyor := lambaAcik;
    FKirli := True;
  end;
end;

procedure TSanalLamba.Vurus;
begin
  FSayac := (FSayac + 1) mod 8;
  DurumuHesapla;
end;

procedure TSanalLamba.ModAyarla(yeniDeger: TLambaModu);
begin
  if FMod = yeniDeger then Exit;
  FMod := yeniDeger;
  FSayac := 0;
  DurumuHesapla;
  FKirli := True;
end;

procedure TSanalLamba.KartKodunuUygula(kodDeger: Byte);
begin
  case kodDeger of
    0: ModAyarla(lmYanSon1Hz);
    1: ModAyarla(lmSabit);
    2: ModAyarla(lmYanSon4Hz);
    6: ModAyarla(lmYanSon4Hz);
  else
    ModAyarla(lmBilinmiyor);
  end;
end;

function TSanalLamba.YenidenCizilmeli: Boolean;
begin
  Result := FKirli;
  FKirli := False;
end;

procedure TSanalLamba.Ciz(dc: HDC; x, y: Integer; zeminRengi: DWord);
var
  zeminRgb, anaRenk: TRgb;
  etkin: Boolean;
  bmpBilgi: TBmiHeader_;
begin
  if (dc = 0) or (Length(FPikseller) = 0) then Exit;
  zeminRgb := RenkRgb(zeminRengi and $FF, (zeminRengi shr 8) and $FF, (zeminRengi shr 16) and $FF);
  etkin := FYaniyor and (FMod <> lmBilinmiyor);
  if FMod = lmBilinmiyor then anaRenk := RenkRgb(80, 86, 98)
  else if FYaniyor then anaRenk := RenkRgb(0, 255, 0)
  else anaRenk := RenkRgb(0, 60, 0);
  LambaCiz(FPikseller, FBoyut, anaRenk, etkin, zeminRgb, False);
  FillChar(bmpBilgi, SizeOf(bmpBilgi), 0);
  bmpBilgi.biSize := SizeOf(TBmiHeader_);
  bmpBilgi.biWidth := FBoyut;
  bmpBilgi.biHeight := FBoyut;
  bmpBilgi.biPlanes := 1;
  bmpBilgi.biBitCount := 32;
  bmpBilgi.biCompression := 0;
  api_SetDIBitsToDevice(dc, x, y, FBoyut, FBoyut, 0, 0, 0, FBoyut, @FPikseller[0], @bmpBilgi, 0);
end;

class function TSanalLamba.YananSimgeOlustur(boyut: Integer): HICON;
var
  renkler: array of DWord;
  maskeler: array of Byte;
  renkBmp, maskeBmp: HBITMAP;
  simgeBilgi: TIconInfo_;
begin
  if boyut < 8 then boyut := 8;
  SetLength(renkler, boyut * boyut);
  LambaCiz(renkler, boyut, RenkRgb(0, 255, 0), True, RenkRgb(0, 0, 0), True);
  SetLength(maskeler, ((boyut + 15) div 16) * 2 * boyut);
  FillChar(maskeler[0], Length(maskeler), 0);
  renkBmp := api_CreateBitmap(boyut, boyut, 1, 32, @renkler[0]);
  maskeBmp := api_CreateBitmap(boyut, boyut, 1, 1, @maskeler[0]);
  Result := 0;
  if (renkBmp <> 0) and (maskeBmp <> 0) then
  begin
    FillChar(simgeBilgi, SizeOf(simgeBilgi), 0);
    simgeBilgi.fIcon := True;
    simgeBilgi.hbmMask := maskeBmp;
    simgeBilgi.hbmColor := renkBmp;
    Result := api_CreateIconIndirect(@simgeBilgi);
  end;
  if renkBmp <> 0 then DeleteObject(renkBmp);
  if maskeBmp <> 0 then DeleteObject(maskeBmp);
end;

{ ================= Pencere ================= }

procedure GosterileniAyarla(i: Integer; const s: UnicodeString);
begin
  if (gEtiketler[i] <> 0) and (gGosterilen[i] <> s) then
  begin
    gGosterilen[i] := s;
    api_SetWindowTextW(gEtiketler[i], PWideChar(gGosterilen[i]));
  end;
end;

function BosIseTire(const s: UnicodeString): UnicodeString;
begin
  if s = '' then Result := '-' else Result := s;
end;

procedure BilgiyiYenile;
var
  bilgi: TKartBilgisi;
  st: UnicodeString;
begin
  if (gPencere = 0) or (not Assigned(gBilgiAl)) then Exit;
  bilgi := gBilgiAl();
  if bilgi.Kurulu then
  begin
    st := PencereBagli;
    gDurumRengi := RENK_YESIL;
  end
  else if bilgi.Mevcut then
  begin
    st := PencereUsbHazir;
    gDurumRengi := RENK_TURUNCU;
  end
  else
  begin
    st := PencereKartYok;
    gDurumRengi := RENK_KIRMIZI;
  end;
  GosterileniAyarla(0, st);
  GosterileniAyarla(1, Bicimle(PencerePortBicimi, [BosIseTire(bilgi.PortAdi), UnicodeString(IntToStr(bilgi.Baud))]));
  if gLamba <> nil then
  begin
    if bilgi.GeriBildirimVar then gLamba.KartKodunuUygula(bilgi.Lamba)
    else gLamba.KartKodunuUygula(255);
    if (gLambaPencere <> 0) and gLamba.YenidenCizilmeli then
      api_InvalidateRect(gLambaPencere, nil, False);
  end;
end;

procedure PencereyiGizle;
begin
  if gPencere <> 0 then ShowWindow(gPencere, SW_HIDE);
end;

procedure FircalariOlustur;
begin
  if gFircaZemin <> 0 then Exit;
  gFircaZemin := CreateSolidBrush(RENK_ZEMIN);
  gFircaYuzey := CreateSolidBrush(RENK_YUZEY);
  gFircaKenar := CreateSolidBrush(RENK_KENAR);
end;

procedure FircalariBirak;
begin
  if gFircaZemin <> 0 then begin DeleteObject(gFircaZemin); gFircaZemin := 0; end;
  if gFircaYuzey <> 0 then begin DeleteObject(gFircaYuzey); gFircaYuzey := 0; end;
  if gFircaKenar <> 0 then begin DeleteObject(gFircaKenar); gFircaKenar := 0; end;
end;

procedure KoyuBaslik(pencere: HWND);
var
  v: DWord;
begin
  try
    v := 1;
    if DwmSetWindowAttribute_(pencere, 20, @v, 4) <> 0 then
      DwmSetWindowAttribute_(pencere, 19, @v, 4);
    v := $00331B0E; DwmSetWindowAttribute_(pencere, 35, @v, 4);
    v := RENK_YAZI;  DwmSetWindowAttribute_(pencere, 36, @v, 4);
    v := $00784426; DwmSetWindowAttribute_(pencere, 34, @v, 4);
  except
  end;
end;

procedure PanelCiz(dc: HDC; x, y, en, h: Integer; const yazi: UnicodeString);
var
  r: TRect;
  eskiYazi: HGDIOBJ;
begin
  r.Left := x;
  r.Top := y;
  r.Right := x + en;
  r.Bottom := y + h;
  api_FillRect(dc, @r, gFircaYuzey);
  api_FrameRect(dc, @r, gFircaKenar);
  SetBkMode(dc, TRANSPARENT);
  SetTextColor(dc, RENK_VURGU);
  eskiYazi := SelectObject(dc, gYaziKalin);
  Inc(r.Left, 10);
  Inc(r.Top, 4);
  api_DrawTextW(dc, PWideChar(yazi), -1, @r, DT_SINGLELINE_ or DT_NOPREFIX_);
  SelectObject(dc, eskiYazi);
end;

procedure PencereyiCiz(pencere: HWND);
var
  ps: TPaintStruct_;
  dc: HDC;
begin
  dc := api_BeginPaint(pencere, @ps);
  try
    PanelCiz(dc, PANEL_SOL, PANEL_UST, PANEL_EN, PANEL_YUK, PencereKartDurumu);
  finally
    api_EndPaint(pencere, @ps);
  end;
end;

{ Durum penceresinin pencere yordamı }
function KartPencereYordami(pencere: HWND; mesaj: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall;
var
  di: PDrawItemStruct_;
begin
  try
    case mesaj of
      WM_CLOSE:
        begin
          PencereyiGizle;
          Exit(0);
        end;
      WM_TIMER:
        begin
          if (wp = KIMLIK_ZAMANLAYICI) and (gLamba <> nil) then
          begin
            gLamba.Vurus;
            if (gLambaPencere <> 0) and gLamba.YenidenCizilmeli then
              api_InvalidateRect(gLambaPencere, nil, False);
          end;
          Exit(0);
        end;
      WM_PAINT:
        begin
          PencereyiCiz(pencere);
          Exit(0);
        end;
      WM_DRAWITEM:
        begin
          di := PDrawItemStruct_(lp);
          if (di <> nil) and (di^.CtlID = KIMLIK_LAMBA) and (gLamba <> nil) then
            gLamba.Ciz(di^.dcItem, di^.rcItem.Left, di^.rcItem.Top, RENK_YUZEY);
          Exit(1);
        end;
      WM_CTLCOLORSTATIC:
        begin
          if HWND(lp) = gEtiketler[0] then SetTextColor(HDC(wp), gDurumRengi)
          else SetTextColor(HDC(wp), RENK_YAZI);
          SetBkColor(HDC(wp), RENK_YUZEY);
          Exit(LRESULT(gFircaYuzey));
        end;
    end;
  except
  end;
  Result := api_DefWindowProcW(pencere, mesaj, wp, lp);
end;

function AltPencereOlustur(ekStil: DWord; const sinif, yazi: UnicodeString; stil: DWord;
  x, y, en, h, kimlik: Integer; yaziTipi: HFONT): HWND;
begin
  Result := api_CreateWindowExW(ekStil, PWideChar(sinif), PWideChar(yazi),
    WS_CHILD or WS_VISIBLE or WS_CLIPSIBLINGS or stil,
    x, y, en, h, gPencere, HMENU(kimlik), HInstance, nil);
  if (Result <> 0) and (yaziTipi <> 0) then
    api_SendMessageW(Result, WM_SETFONT, WPARAM(yaziTipi), 1);
end;

procedure SimgeleriKur(pencere: HWND);
begin
  if gSimgeKucuk = 0 then gSimgeKucuk := TSanalLamba.YananSimgeOlustur(GetSystemMetrics(SM_CXSMICON_));
  if gSimgeBuyuk = 0 then gSimgeBuyuk := TSanalLamba.YananSimgeOlustur(GetSystemMetrics(SM_CXICON_));
  if gSimgeKucuk <> 0 then api_SendMessageW(pencere, WM_SETICON, ICON_SMALL_, LPARAM(gSimgeKucuk));
  if gSimgeBuyuk <> 0 then api_SendMessageW(pencere, WM_SETICON, ICON_BIG_, LPARAM(gSimgeBuyuk));
end;

procedure YazilariOlustur;
begin
  if gYaziNormal = 0 then
    gYaziNormal := api_CreateFontW(-12, 0, 0, 0, 400, 0, 0, 0, 1, 0, 0, 0, 0, PWideChar(YAZI_TIPI_ADI));
  if gYaziKalin = 0 then
    gYaziKalin := api_CreateFontW(-12, 0, 0, 0, 700, 0, 0, 0, 1, 0, 0, 0, 0, PWideChar(YAZI_TIPI_ADI));
end;

procedure SimgeleriBirak;
begin
  if gSimgeKucuk <> 0 then begin DestroyIcon(gSimgeKucuk); gSimgeKucuk := 0; end;
  if gSimgeBuyuk <> 0 then begin DestroyIcon(gSimgeBuyuk); gSimgeBuyuk := 0; end;
end;

{ Durum penceresini ve denetimlerini oluşturur. }
procedure KartPenceresiOlustur(sahip: HWND);
var
  sinifKaydi: TWndClassW_;
  stil: DWord;
  r, anaPencere: TRect;
  solKonum, ustKonum, i: Integer;
begin
  FircalariOlustur;
  if not gSinifHazir then
  begin
    FillChar(sinifKaydi, SizeOf(sinifKaydi), 0);
    sinifKaydi.lpfnWndProc := @KartPencereYordami;
    sinifKaydi.hInstanceW := HInstance;
    sinifKaydi.hCursorW := api_LoadCursorW(0, PWideChar(PtrUInt(IDC_ARROW_)));
    sinifKaydi.hbrBackground := gFircaZemin;
    sinifKaydi.lpszClassName := PWideChar(PENCERE_SINIFI);
    if api_RegisterClassW(@sinifKaydi) = 0 then Exit;
    gSinifHazir := True;
  end;
  YazilariOlustur;
  stil := WS_CAPTION or WS_SYSMENU or WS_CLIPCHILDREN;
  r.Left := 0;
  r.Top := 0;
  r.Right := ALAN_EN;
  r.Bottom := ALAN_YUK;
  api_AdjustWindowRectEx(@r, stil, False, 0);
  solKonum := 100;
  ustKonum := 100;
  if (sahip <> 0) and Boolean(api_GetWindowRect(sahip, @anaPencere)) then
  begin
    solKonum := anaPencere.Left + 200;
    ustKonum := anaPencere.Top + 100;
  end;
  gPencere := api_CreateWindowExW(0, PWideChar(PENCERE_SINIFI), PWideChar(KartPencereBasligi), stil,
    solKonum, ustKonum, r.Right - r.Left, r.Bottom - r.Top, sahip, 0, HInstance, nil);
  if gPencere = 0 then Exit;
  KoyuBaslik(gPencere);
  SimgeleriKur(gPencere);
  if gLamba = nil then gLamba := TSanalLamba.Create(LAMBA_BOYU);
  gLambaPencere := AltPencereOlustur(0, SINIF_STATIK, '', SS_OWNERDRAW_, 16, PANEL_UST + 24, LAMBA_BOYU, LAMBA_BOYU, KIMLIK_LAMBA, 0);
  gEtiketler[0] := AltPencereOlustur(0, SINIF_STATIK, '', 0, 44, PANEL_UST + 26, 312, 18, 0, gYaziKalin);
  gEtiketler[1] := AltPencereOlustur(0, SINIF_STATIK, '', 0, 16, PANEL_UST + 56, 340, 18, 0, gYaziNormal);
  api_SetTimer(gPencere, KIMLIK_ZAMANLAYICI, LAMBA_VURUS_MS, nil);
  for i := 0 to SATIR_SAYISI - 1 do gGosterilen[i] := #1;
end;

procedure AltPencereleriSil;
var
  i: Integer;
begin
  for i := 0 to SATIR_SAYISI - 1 do gEtiketler[i] := 0;
  gLambaPencere := 0;
end;

procedure KartPenceresiGoster(sahip: HWND; bilgiAl: TKartBilgisiFn);
var
  i: Integer;
begin
  gBilgiAl := bilgiAl;
  if gPencere = 0 then KartPenceresiOlustur(sahip);
  if gPencere = 0 then Exit;
  if not IsWindowVisible(gPencere) then
  begin
    for i := 0 to SATIR_SAYISI - 1 do gGosterilen[i] := #1;
    BilgiyiYenile;
    ShowWindow(gPencere, SW_SHOWNORMAL);
  end;
  SetForegroundWindow(gPencere);
end;

procedure KartPenceresiGuncelle;
var
  t: QWord;
begin
  if (gPencere = 0) or (not IsWindowVisible(gPencere)) then Exit;
  t := SaatMs64;
  if t - gSonYenileme < YENILEME_MS then Exit;
  gSonYenileme := t;
  BilgiyiYenile;
end;

procedure KartPenceresiSerbest;
begin
  HizUyarisiKapat;
  if gPencere <> 0 then
  begin
    api_KillTimer(gPencere, KIMLIK_ZAMANLAYICI);
    DestroyWindow(gPencere);
    gPencere := 0;
  end;
  FreeAndNil(gLamba);
  AltPencereleriSil;
  SimgeleriBirak;
  if gYaziNormal <> 0 then begin DeleteObject(gYaziNormal); gYaziNormal := 0; end;
  if gYaziKalin <> 0 then begin DeleteObject(gYaziKalin); gYaziKalin := 0; end;
  if gSinifHazir then
  begin
    api_UnregisterClassW(PWideChar(PENCERE_SINIFI), HInstance);
    gSinifHazir := False;
  end;
  if gUyariSinifHazir then
  begin
    api_UnregisterClassW(PWideChar(UYARI_SINIFI), HInstance);
    gUyariSinifHazir := False;
  end;
  if gFircaVurgu <> 0 then begin DeleteObject(gFircaVurgu); gFircaVurgu := 0; end;
  FircalariBirak;
  gBilgiAl := nil;
end;

{ ================= Eksen hızı uyarısı ================= }

procedure UyariyiCiz(pencere: HWND);
var
  ps: TPaintStruct_;
  dc: HDC;
  r: TRect;
  eskiYazi: HGDIOBJ;
begin
  dc := api_BeginPaint(pencere, @ps);
  try
    PanelCiz(dc, PANEL_SOL, PANEL_UST, UYARI_EN - 2 * PANEL_SOL,
      UYARI_METIN_UST + gUyariMetinYuk + 12, HizUyarisiPanel);
    r.Left := PANEL_SOL + 10;
    r.Top := PANEL_UST + UYARI_METIN_UST;
    r.Right := UYARI_EN - PANEL_SOL - 10;
    r.Bottom := r.Top + gUyariMetinYuk;
    SetBkMode(dc, TRANSPARENT);
    SetTextColor(dc, RENK_YAZI);
    eskiYazi := SelectObject(dc, gYaziNormal);
    api_DrawTextW(dc, PWideChar(gUyariMetni), -1, @r, DT_WORDBREAK_ or DT_NOPREFIX_);
    SelectObject(dc, eskiYazi);
  finally
    api_EndPaint(pencere, @ps);
  end;
end;

{ Temalı Tamam düğmesi: yüzey renginde zemin, basılıyken kenar rengi,
  vurgu renginde çerçeve. }
procedure DugmeCiz(di: PDrawItemStruct_);
var
  r: TRect;
  eskiYazi: HGDIOBJ;
begin
  r := di^.rcItem;
  if (di^.itemState and ODS_SELECTED_) <> 0 then
    api_FillRect(di^.dcItem, @r, gFircaKenar)
  else
    api_FillRect(di^.dcItem, @r, gFircaYuzey);
  api_FrameRect(di^.dcItem, @r, gFircaVurgu);
  SetBkMode(di^.dcItem, TRANSPARENT);
  SetTextColor(di^.dcItem, RENK_YAZI);
  eskiYazi := SelectObject(di^.dcItem, gYaziKalin);
  api_DrawTextW(di^.dcItem, PWideChar(HizDugmeTamam), -1, @r,
    DT_CENTER_ or DT_VCENTER_ or DT_SINGLELINE_ or DT_NOPREFIX_);
  SelectObject(di^.dcItem, eskiYazi);
end;

{ Uyarı penceresinin pencere yordamı: Tamam ya da kapatma pencereyi kapatır. }
function UyariPencereYordami(pencere: HWND; mesaj: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall;
var
  di: PDrawItemStruct_;
begin
  try
    case mesaj of
      WM_CLOSE:
        begin
          HizUyarisiKapat;
          Exit(0);
        end;
      WM_PAINT:
        begin
          UyariyiCiz(pencere);
          Exit(0);
        end;
      WM_DRAWITEM:
        begin
          di := PDrawItemStruct_(lp);
          if (di <> nil) and (di^.CtlType = ODT_BUTTON_) then
          begin
            DugmeCiz(di);
            Exit(1);
          end;
        end;
      WM_COMMAND:
        begin
          if ((LongInt(wp) and $FFFF) = KIMLIK_TAMAM) and
             (((LongInt(wp) shr 16) and $FFFF) = BN_CLICKED_) then
            HizUyarisiKapat;
          Exit(0);
        end;
    end;
  except
  end;
  Result := api_DefWindowProcW(pencere, mesaj, wp, lp);
end;

procedure HizUyarisiGoster(const metin: UnicodeString);
var
  sinifKaydi: TWndClassW_;
  stil: DWord;
  r: TRect;
  dc: HDC;
  eskiYazi: HGDIOBJ;
  en, yuk, dugmeUst: Integer;
begin
  if gUyari <> 0 then Exit;
  gUyariMetni := metin;
  FircalariOlustur;
  YazilariOlustur;
  if gFircaVurgu = 0 then gFircaVurgu := CreateSolidBrush(RENK_VURGU);
  if not gUyariSinifHazir then
  begin
    FillChar(sinifKaydi, SizeOf(sinifKaydi), 0);
    sinifKaydi.lpfnWndProc := @UyariPencereYordami;
    sinifKaydi.hInstanceW := HInstance;
    sinifKaydi.hCursorW := api_LoadCursorW(0, PWideChar(PtrUInt(IDC_ARROW_)));
    sinifKaydi.hbrBackground := gFircaZemin;
    sinifKaydi.lpszClassName := PWideChar(UYARI_SINIFI);
    if api_RegisterClassW(@sinifKaydi) <> 0 then gUyariSinifHazir := True;
  end;
  { Metnin yüksekliği; pencere boyu buna göre }
  r.Left := 0;
  r.Top := 0;
  r.Right := UYARI_EN - 2 * PANEL_SOL - 20;
  r.Bottom := 0;
  dc := api_GetDC(0);
  eskiYazi := SelectObject(dc, gYaziNormal);
  api_DrawTextW(dc, PWideChar(gUyariMetni), -1, @r, DT_CALCRECT_ or DT_WORDBREAK_ or DT_NOPREFIX_);
  SelectObject(dc, eskiYazi);
  api_ReleaseDC(0, dc);
  gUyariMetinYuk := r.Bottom - r.Top;
  dugmeUst := PANEL_UST + UYARI_METIN_UST + gUyariMetinYuk + 12 + 10;
  stil := WS_CAPTION or WS_SYSMENU or WS_CLIPCHILDREN;
  r.Left := 0;
  r.Top := 0;
  r.Right := UYARI_EN;
  r.Bottom := dugmeUst + DUGME_YUK + 10;
  api_AdjustWindowRectEx(@r, stil, False, WS_EX_TOPMOST_);
  en := r.Right - r.Left;
  yuk := r.Bottom - r.Top;
  if gUyariSinifHazir then
    gUyari := api_CreateWindowExW(WS_EX_TOPMOST_, PWideChar(UYARI_SINIFI), PWideChar(HizUyarisiBasligi),
      stil, (GetSystemMetrics(SM_CXSCREEN_) - en) div 2, (GetSystemMetrics(SM_CYSCREEN_) - yuk) div 2,
      en, yuk, 0, 0, HInstance, nil);
  if gUyari = 0 then
  begin
    { Pencere oluşturulamadı: aynı uyarı Windows ileti kutusuyla gösterilir. }
    api_MessageBoxW(0, PWideChar(HizUyarisiPanel + #13#10#13#10 + gUyariMetni),
      PWideChar(HizUyarisiBasligi), MB_OK or MB_ICONWARNING or MB_TOPMOST_);
    Exit;
  end;
  KoyuBaslik(gUyari);
  SimgeleriKur(gUyari);
  api_CreateWindowExW(0, PWideChar(SINIF_DUGME), nil,
    WS_CHILD or WS_VISIBLE or WS_TABSTOP or BS_OWNERDRAW_,
    UYARI_EN - PANEL_SOL - DUGME_EN, dugmeUst, DUGME_EN, DUGME_YUK,
    gUyari, HMENU(KIMLIK_TAMAM), HInstance, nil);
  ShowWindow(gUyari, SW_SHOWNORMAL);
  SetForegroundWindow(gUyari);
end;

function HizUyarisiAcik: Boolean;
begin
  Result := gUyari <> 0;
end;

procedure HizUyarisiKapat;
var
  pencere: HWND;
begin
  pencere := gUyari;
  gUyari := 0;
  if pencere <> 0 then DestroyWindow(pencere);
end;

end.
