{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uSistemApi.pas - Win32 API tanımları
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  Windows biriminin FPC sürümleri arasında imzası değişen ya da var/const
  parametre sorunu çıkarabilecek API'ler burada açıkça tanımlıdır.
}
unit uSistemApi;

{$mode objfpc}{$H+}
{$R-}{$Q-}

interface

uses
  Windows;

const
  CLRRTS_ = 4;
  CLRDTR_ = 6;
  PURGE_ALL_ = $0F;
  ERROR_IO_PENDING_ = 997;
  WAIT_OBJECT_0_ = 0;
  WAIT_TIMEOUT_ = 258;
  GWL_WNDPROC_ = -4;
  MF_STRING_ = $0000;
  MF_BYCOMMAND_ = $0000;
  MF_POPUP_ = $0010;
  MF_BYPOSITION_ = $0400;
  IDC_ARROW_ = 32512;
  ICON_SMALL_ = 0;
  ICON_BIG_ = 1;
  SM_CXICON_ = 11;
  SM_CXSMICON_ = 49;
  PROCESS_POWER_THROTTLING_ = 4;

type
  TOverlapped_ = record
    Internal: DWORD;
    InternalHigh: DWORD;
    Offset: DWORD;
    OffsetHigh: DWORD;
    hEvent: THandle;
  end;
  POverlapped_ = ^TOverlapped_;

  TDCB_ = packed record
    DCBlength: DWORD;
    BaudRate: DWORD;
    Flags: DWORD;
    wReserved: Word;
    XonLim: Word;
    XoffLim: Word;
    ByteSize: Byte;
    Parity: Byte;
    StopBits: Byte;
    XonChar: AnsiChar;
    XoffChar: AnsiChar;
    ErrorChar: AnsiChar;
    EofChar: AnsiChar;
    EvtChar: AnsiChar;
    wReserved1: Word;
  end;

  TCommTimeouts_ = record
    ReadIntervalTimeout: DWORD;
    ReadTotalTimeoutMultiplier: DWORD;
    ReadTotalTimeoutConstant: DWORD;
    WriteTotalTimeoutMultiplier: DWORD;
    WriteTotalTimeoutConstant: DWORD;
  end;

  TPowerThrottling_ = record
    Version: DWORD;
    ControlMask: DWORD;
    StateMask: DWORD;
  end;

  TWndClassW_ = record
    stil: UINT;
    lpfnWndProc: Pointer;
    cbClsExtra: Integer;
    cbWndExtra: Integer;
    hInstanceW: HINST;
    hIconW: HICON;
    hCursorW: HCURSOR;
    hbrBackground: HBRUSH;
    lpszMenuName: PWideChar;
    lpszClassName: PWideChar;
  end;

  TPaintStruct_ = record
    dcPaint: HDC;
    fErase: BOOL;
    rcPaint: TRect;
    fRestore: BOOL;
    fIncUpdate: BOOL;
    rgbReserved: array[0..31] of Byte;
  end;

  TDrawItemStruct_ = record
    CtlType: UINT;
    CtlID: UINT;
    itemID: UINT;
    itemAction: UINT;
    itemState: UINT;
    hwndItem: HWND;
    dcItem: HDC;
    rcItem: TRect;
    itemData: PtrUInt;
  end;
  PDrawItemStruct_ = ^TDrawItemStruct_;

  TBmiHeader_ = record
    biSize: DWORD;
    biWidth: LongInt;
    biHeight: LongInt;
    biPlanes: Word;
    biBitCount: Word;
    biCompression: DWORD;
    biSizeImage: DWORD;
    biXPelsPerMeter: LongInt;
    biYPelsPerMeter: LongInt;
    biClrUsed: DWORD;
    biClrImportant: DWORD;
  end;

  TIconInfo_ = record
    fIcon: BOOL;
    xHotspot: DWORD;
    yHotspot: DWORD;
    hbmMask: HBITMAP;
    hbmColor: HBITMAP;
  end;

{ kernel32 }
function api_CreateFileA(isim: PAnsiChar; erisim, paylasim: DWORD; sa: Pointer;
  olusturma, flags: DWORD; sablon: THandle): THandle; stdcall; external 'kernel32.dll' name 'CreateFileA';
function api_ReadFile(h: THandle; arabellek: Pointer; n: DWORD; okunan: PDWORD;
  ov: POverlapped_): BOOL; stdcall; external 'kernel32.dll' name 'ReadFile';
function api_WriteFile(h: THandle; arabellek: Pointer; n: DWORD; yazilanAdet: PDWORD;
  ov: POverlapped_): BOOL; stdcall; external 'kernel32.dll' name 'WriteFile';
function api_GetOverlappedResult(h: THandle; ov: POverlapped_; var n: DWORD;
  bekleme: BOOL): BOOL; stdcall; external 'kernel32.dll' name 'GetOverlappedResult';
function api_CancelIo(h: THandle): BOOL; stdcall; external 'kernel32.dll' name 'CancelIo';
function api_CreateEventW(sa: Pointer; elleSifirla, ilkDurum: BOOL;
  isim: PWideChar): THandle; stdcall; external 'kernel32.dll' name 'CreateEventW';
function api_GetCommState(h: THandle; dcb: Pointer): BOOL; stdcall; external 'kernel32.dll' name 'GetCommState';
function api_SetCommState(h: THandle; dcb: Pointer): BOOL; stdcall; external 'kernel32.dll' name 'SetCommState';
function api_SetCommTimeouts(h: THandle; t: Pointer): BOOL; stdcall; external 'kernel32.dll' name 'SetCommTimeouts';
function api_SetupComm(h: THandle; girisBoyu, cikisBoyu: DWORD): BOOL; stdcall; external 'kernel32.dll' name 'SetupComm';
function api_PurgeComm(h: THandle; flags: DWORD): BOOL; stdcall; external 'kernel32.dll' name 'PurgeComm';
function api_EscapeCommFunction(h: THandle; islev: DWORD): BOOL; stdcall; external 'kernel32.dll' name 'EscapeCommFunction';
function api_QueryPerformanceCounter(var v: Int64): BOOL; stdcall; external 'kernel32.dll' name 'QueryPerformanceCounter';
function api_QueryPerformanceFrequency(var v: Int64): BOOL; stdcall; external 'kernel32.dll' name 'QueryPerformanceFrequency';

{ winmm }
function api_timeBeginPeriod(p: UINT): UINT; stdcall; external 'winmm.dll' name 'timeBeginPeriod';
function api_timeEndPeriod(p: UINT): UINT; stdcall; external 'winmm.dll' name 'timeEndPeriod';

{ user32 }
function api_SetWindowLongA(pencere: HWND; sira: Integer; v: LongInt): LongInt; stdcall; external 'user32.dll' name 'SetWindowLongA';
function api_SetWindowLongW(pencere: HWND; sira: Integer; v: LongInt): LongInt; stdcall; external 'user32.dll' name 'SetWindowLongW';
function api_GetWindowLongA(pencere: HWND; sira: Integer): LongInt; stdcall; external 'user32.dll' name 'GetWindowLongA';
function api_GetWindowLongW(pencere: HWND; sira: Integer): LongInt; stdcall; external 'user32.dll' name 'GetWindowLongW';
function api_CallWindowProcA(onceki: Pointer; pencere: HWND; mesaj: UINT; wp: WPARAM;
  lp: LPARAM): LRESULT; stdcall; external 'user32.dll' name 'CallWindowProcA';
function api_CallWindowProcW(onceki: Pointer; pencere: HWND; mesaj: UINT; wp: WPARAM;
  lp: LPARAM): LRESULT; stdcall; external 'user32.dll' name 'CallWindowProcW';
function api_DefWindowProcW(pencere: HWND; mesaj: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall; external 'user32.dll' name 'DefWindowProcW';
function api_EnumWindows(yordam: Pointer; lp: LPARAM): BOOL; stdcall; external 'user32.dll' name 'EnumWindows';
function api_GetWindowThreadProcessId(pencere: HWND; pid: PDWORD): DWORD; stdcall; external 'user32.dll' name 'GetWindowThreadProcessId';
function api_SetTimer(pencere: HWND; kimlik: UINT_PTR; aralik: UINT; yordam: Pointer): UINT_PTR; stdcall; external 'user32.dll' name 'SetTimer';
function api_KillTimer(pencere: HWND; kimlik: UINT_PTR): BOOL; stdcall; external 'user32.dll' name 'KillTimer';
function api_GetMenuStringA(menu: HMENU; oge: UINT; arabellek: PAnsiChar; azamiAdet: Integer;
  flags: UINT): Integer; stdcall; external 'user32.dll' name 'GetMenuStringA';
function api_AppendMenuA(menu: HMENU; flags: UINT; kimlik: UINT_PTR; metin: PAnsiChar): BOOL; stdcall; external 'user32.dll' name 'AppendMenuA';
function api_DeleteMenu(menu: HMENU; yer, flags: UINT): BOOL; stdcall; external 'user32.dll' name 'DeleteMenu';
function api_MessageBoxW(pencere: HWND; metin, baslik: PWideChar; t: UINT): Integer; stdcall; external 'user32.dll' name 'MessageBoxW';
function api_RegisterClassW(sinifKaydi: Pointer): ATOM; stdcall; external 'user32.dll' name 'RegisterClassW';
function api_UnregisterClassW(sinif: PWideChar; ornek: HINST): BOOL; stdcall; external 'user32.dll' name 'UnregisterClassW';
function api_CreateWindowExW(ekStil: DWORD; sinif, pencereBasligi: PWideChar; stil: DWORD;
  x, y, en, h: Integer; ust: HWND; menu: HMENU; ornek: HINST;
  ekVeri: Pointer): HWND; stdcall; external 'user32.dll' name 'CreateWindowExW';
function api_SetWindowTextW(pencere: HWND; metin: PWideChar): BOOL; stdcall; external 'user32.dll' name 'SetWindowTextW';
function api_SendMessageW(pencere: HWND; mesaj: UINT; wp: WPARAM; lp: LPARAM): LRESULT; stdcall; external 'user32.dll' name 'SendMessageW';
function api_GetDC(pencere: HWND): HDC; stdcall; external 'user32.dll' name 'GetDC';
function api_ReleaseDC(pencere: HWND; dc: HDC): Integer; stdcall; external 'user32.dll' name 'ReleaseDC';
function api_LoadCursorW(ornek: HINST; isim: PWideChar): HCURSOR; stdcall; external 'user32.dll' name 'LoadCursorW';
function api_AdjustWindowRectEx(r: PRect; stil: DWORD; menu: BOOL; ekStil: DWORD): BOOL; stdcall; external 'user32.dll' name 'AdjustWindowRectEx';
function api_GetWindowRect(pencere: HWND; r: PRect): BOOL; stdcall; external 'user32.dll' name 'GetWindowRect';
function api_ReleaseCapture: BOOL; stdcall; external 'user32.dll' name 'ReleaseCapture';
function api_BeginPaint(pencere: HWND; ps: Pointer): HDC; stdcall; external 'user32.dll' name 'BeginPaint';
function api_EndPaint(pencere: HWND; ps: Pointer): BOOL; stdcall; external 'user32.dll' name 'EndPaint';
function api_InvalidateRect(pencere: HWND; r: PRect; sil: BOOL): BOOL; stdcall; external 'user32.dll' name 'InvalidateRect';
function api_FillRect(dc: HDC; r: PRect; firca: HBRUSH): Integer; stdcall; external 'user32.dll' name 'FillRect';
function api_FrameRect(dc: HDC; r: PRect; firca: HBRUSH): Integer; stdcall; external 'user32.dll' name 'FrameRect';
function api_DrawTextW(dc: HDC; metin: PWideChar; count: Integer; r: PRect;
  bicim: UINT): Integer; stdcall; external 'user32.dll' name 'DrawTextW';
function api_CreateIconIndirect(simgeBilgi: Pointer): HICON; stdcall; external 'user32.dll' name 'CreateIconIndirect';

{ gdi32 }
function api_CreateFontW(h, en, egim, yonelim, kalinlik: Integer; egik, altiCizili, ustuCizili,
  karakterKumesi, cikisHassasiyeti, kirpmaHassasiyeti, kalite, aralikVeAile: DWORD;
  yaziTipiAdi: PWideChar): HFONT; stdcall; external 'gdi32.dll' name 'CreateFontW';
function api_CreateBitmap(en, h: Integer; duzlemler, bitSayisi: UINT; bitler: Pointer): HBITMAP; stdcall; external 'gdi32.dll' name 'CreateBitmap';
function api_SetDIBitsToDevice(dc: HDC; xDest, yDest: Integer; en, h: DWORD;
  xSrc, ySrc: Integer; ilkSatir, satirlar: UINT; bitler: Pointer; bmpBilgi: Pointer;
  renkKullanimi: UINT): Integer; stdcall; external 'gdi32.dll' name 'SetDIBitsToDevice';

{ Çalışma anında yüklenen API'ler (eski Windows sürümlerinde yok olabilir) }
function SaatMs64: QWord;
function SetProcessInformation_(h: THandle; bilgiSinifi: Integer; bilgiAdres: Pointer; bayt: DWORD): Boolean;
function DwmSetWindowAttribute_(pencere: HWND; ozellik: DWORD; deger: Pointer; bayt: DWORD): LongInt;

implementation

type
  TGetTickCount64Fn = function: QWord; stdcall;
  TSetProcessInformationFn = function(h: THandle; bilgiSinifi: Integer; bilgiAdres: Pointer; bayt: DWORD): BOOL; stdcall;
  TDwmSetWindowAttributeFn = function(pencere: HWND; ozellik: DWORD; deger: Pointer; bayt: DWORD): LongInt; stdcall;

var
  pGetTickCount64: TGetTickCount64Fn = nil;
  pSetProcessInformation: TSetProcessInformationFn = nil;
  pDwmSetWindowAttribute: TDwmSetWindowAttributeFn = nil;
  gDwmYuklendi: Boolean = False;

function SaatMs64: QWord;
begin
  if Assigned(pGetTickCount64) then
    Result := pGetTickCount64()
  else
    Result := GetTickCount;
end;

function SetProcessInformation_(h: THandle; bilgiSinifi: Integer; bilgiAdres: Pointer; bayt: DWORD): Boolean;
begin
  Result := False;
  if Assigned(pSetProcessInformation) then
    Result := pSetProcessInformation(h, bilgiSinifi, bilgiAdres, bayt);
end;

function DwmSetWindowAttribute_(pencere: HWND; ozellik: DWORD; deger: Pointer; bayt: DWORD): LongInt;
var
  kitaplik: HMODULE;
begin
  if not gDwmYuklendi then
  begin
    gDwmYuklendi := True;
    kitaplik := LoadLibraryA('dwmapi.dll');
    if kitaplik <> 0 then
      pDwmSetWindowAttribute := TDwmSetWindowAttributeFn(GetProcAddress(kitaplik, 'DwmSetWindowAttribute'));
  end;
  if Assigned(pDwmSetWindowAttribute) then
    Result := pDwmSetWindowAttribute(pencere, ozellik, deger, bayt)
  else
    Result := -1;
end;

procedure KernelFonksiyonlariniYukle;
var
  k: HMODULE;
begin
  k := GetModuleHandleA('kernel32.dll');
  if k = 0 then Exit;
  pGetTickCount64 := TGetTickCount64Fn(GetProcAddress(k, 'GetTickCount64'));
  pSetProcessInformation := TSetProcessInformationFn(GetProcAddress(k, 'SetProcessInformation'));
end;

initialization
  KernelFonksiyonlariniYukle;

end.
