{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uCihaz.pas - üst düzey denetleyici
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  Mach3 olaylarını (hareket, jog, bekleme, prob, sıfırlama) karta bağlar.
  Mach3 yörünge tamponundaki planlanmış hareketleri okuyup 5 ms'lik dilimler
  halinde TKartKatmani'na verir.
}
unit uCihaz;

{$mode objfpc}{$H+}
{$codepage utf8}
{$R-}{$Q-}

interface

uses
  Windows, SysUtils, Math, uSistemApi, uMesajlar, uKartProtokol, uAnaProgram, uKartKatmani;

const
  JOG_ARTI_YON = 0;
  JOG_HIZ_BOLENI = 1.0;
  JOG_YEDEK_HIZ = 1000.0;
  JOG_ZAMANLAYICI_MS = 10;
  TEK_EKSEN_JOG = False;

type
  TCihaz = class
  private
    FAnaProgram: TAnaProgram;
    FKart: TKartKatmani;
    FYorungeSayac: DWord;
    FJogEtkin: array[0..EKSEN_SAYISI - 1] of Boolean;
    FJogYonu: array[0..EKSEN_SAYISI - 1] of Integer;
    FJogHizi: array[0..EKSEN_SAYISI - 1] of Double;
    FJogYorungeIzi: DWord;
    FSonVurus: QWord;
    FTusSayisi: array[0..EKSEN_SAYISI - 1] of Integer;
    FJogKilidi: Boolean;
    FOdakKilidi: Boolean;
    FJogVurusZamani: QWord;
    FSifirlamadaydi: Boolean;
    FTakiliZamani: QWord;
    FBeklemeEtkin: Boolean;
    FBeklemeBaslangic: QWord;
    FBeklemeMs: QWord;
    FAcilisAdimi: Integer;
    FAdimKonum: TEksenReal;
    FHizlar: TEksenReal;
    FBayrakBekliyor: array[0..6] of Boolean;
    FTusYokZamani: QWord;

    procedure AcilisHizmeti;
    procedure BekleyenHareketiGonder;
    procedure JogZamanlayiciBaslat;
    procedure JogZamanlayiciDurdur;
    procedure JogHesapla;
    procedure JogBayraklariniSil(eksen: Integer);
    procedure BekleyenBayraklariTemizle(hemen: Boolean);
    function JogDevamEdiyor: Boolean;
    procedure OdagiDenetle;
    procedure TumJoguDurdur;
    function TusBasiliMi: Boolean;
    procedure BeklemeHizmeti;
    function IslemSuruyor: Boolean;
    procedure HareketiTemizle;
    procedure KilidiDenetle;
    procedure JoguKes;
    procedure JogTusuDenetle;
    procedure TakiliJogDenetle;
  public
    constructor Create;
    destructor Destroy; override;

    procedure DenetimiBaslat;
    procedure AcilisSonrasi;
    procedure Sonlandir;
    procedure PencereyiGoster(sahip: HWND);
    procedure PencereyiGuncelle;
    procedure PencereyiBirak;
    procedure Guncelle;
    procedure JogBaslat(eksen, yonKodu: SmallInt; hizOrani: Double);
    procedure JogVurusu;
    procedure JogBitir(eksen: SmallInt);
    procedure Bekle(time: Double);
    procedure ProbIstegi;
    procedure ReferansaGit(eksen: SmallInt);
    procedure Temizle(flags: SmallInt);
    procedure Sifirla;
    function PencereEtkilesimi: Boolean;
    function TasimadaTusDenetle: Boolean;
  end;

implementation

var
  gJogCihaz: TCihaz = nil;
  gJogZamanlayici: UINT_PTR = 0;

{ Jog sırasında akıcı ve gecikmesiz hareket için 10 ms Windows zamanlayıcısı. }
procedure JogZamanlayiciYordami(pencere: HWND; mesaj: UINT; kimlik: UINT_PTR; time: DWORD); stdcall;
begin
  try
    if gJogCihaz <> nil then gJogCihaz.JogVurusu;
  except
  end;
end;

{ Klavye odağı bir Mach3 penceresindeyse True. }
function ProgramOnPlanda: Boolean;
var
  pencere: HWND;
  pid: DWORD;
begin
  Result := False;
  pencere := GetForegroundWindow;
  if pencere = 0 then Exit;
  pid := 0;
  api_GetWindowThreadProcessId(pencere, @pid);
  Result := pid = GetCurrentProcessId;
end;

{ Herhangi bir klavye tuşu basılıysa True. }
function KlavyeTusuBasili: Boolean;
var
  k: Integer;
begin
  Result := False;
  for k := 8 to 254 do
    if GetAsyncKeyState(k) < 0 then Exit(True);
end;

constructor TCihaz.Create;
begin
  inherited Create;
  FSonVurus := SaatMs64;
  FAcilisAdimi := -1;
  FAnaProgram := TAnaProgram.Create;
  FKart := TKartKatmani.Create(FAnaProgram);
  gJogCihaz := Self;
end;

destructor TCihaz.Destroy;
begin
  JogZamanlayiciDurdur;
  if gJogCihaz = Self then gJogCihaz := nil;
  FKart.Free;
  FAnaProgram.Free;
  inherited Destroy;
end;

procedure TCihaz.DenetimiBaslat;
begin
  MantikYaz(GorunumYaziciAcik, False);
end;

procedure TCihaz.AcilisSonrasi;
begin
  FAcilisAdimi := 0;
  FKart.Baslat;
end;

{ Açılıştan sonra bir kez çalışır: Mach3'ü sıfırlamaya (acil stop) alır.
  Koordinatlar açılışta sıfırlanmaz. }
procedure TCihaz.AcilisHizmeti;
begin
  if FAcilisAdimi < 0 then Exit;
  Inc(FAcilisAdimi);
  if FAcilisAdimi = 1 then
  begin
    if not ProgramSifirlamada then FAnaProgram.SifirlamaDugmesineBas;
    FAcilisAdimi := -1;
  end;
end;

procedure TCihaz.Sonlandir;
begin
  JogZamanlayiciDurdur;
  FKart.Sonlandir;
end;

procedure TCihaz.PencereyiGoster(sahip: HWND);
begin
  FKart.PencereyiGoster(sahip);
end;

procedure TCihaz.PencereyiGuncelle;
begin
  FKart.PencereyiGuncelle;
end;

procedure TCihaz.PencereyiBirak;
begin
  FKart.PencereyiBirak;
end;

procedure TCihaz.Guncelle;
begin
  BeklemeHizmeti;
  AcilisHizmeti;
  KilidiDenetle;
  if ProgramBenzetimde then Exit;
  if ProgramSifirlamada then
  begin
    if not FSifirlamadaydi then
    begin
      FSifirlamadaydi := True;
      TumJoguDurdur;
      BekleyenBayraklariTemizle(True);
      HareketiTemizle;
      if TusBasiliMi then FJogKilidi := True;
    end;
    FKart.KonumuGuncelle;
    Exit;
  end;
  FSifirlamadaydi := False;
  OdagiDenetle;
  JogTusuDenetle;
  BekleyenHareketiGonder;
  if (gJogZamanlayici <> 0) and FKart.HizliJog and (SaatMs64 - FJogVurusZamani > 100) then
    FKart.HizliJog := False;
  JogHesapla;
  FKart.KonumuGuncelle;
  BekleyenBayraklariTemizle(False);
  TakiliJogDenetle;
end;

{ Kartın tamponunda yer olduğu sürece Mach3 tamponundaki yeni yörünge
  noktalarını karta aktarır. }
procedure TCihaz.BekleyenHareketiGonder;
var
  sira: Integer;
  hareket: TGMoves;
begin
  { Jog (yavaşlama dahil) bitmeden Mach3'ün planladığı hareket yanlış konumdan
    planlanmıştır: Mach3 jog sırasında konumu bilmez. Bu noktaları karta
    gönderme, at ve kullanıcıyı uyar. Jog bitince Mach3 konumu eşitler,
    komut yeniden verildiğinde doğru planlanır. }
  if JogDevamEdiyor then
  begin
    if EngYorungeBas^ <> EngYorungeSira^ then
    begin
      EngYorungeSira^ := EngYorungeBas^;
      FKart.Temizle;
      FAnaProgram.GkodBitti;
      { Mach3 hareket başlatınca jog'u kendi tarafında bırakır ama JogOff
        göndermez. Jog'u burada biz durduruyoruz; yeni jog için tuşların
        bırakılması gerekir. }
      JoguKes;
      FJogKilidi := True;
      DurumMesaji(MsjJogBitmedenHareket);
    end;
    Exit;
  end;
  while (EngYorungeBas^ <> EngYorungeSira^) and FKart.KabulEdebilir do
  begin
    Inc(FYorungeSayac);
    sira := EngYorungeSira^ and $FFF;
    EngGosterilenSatir^ := EngYorungeKimlik(sira)^;
    hareket := PlnHareket(sira)^;
    FAnaProgram.HareketAdimlari(hareket, FAdimKonum);
    FKart.GkodDilimi(FAdimKonum);
    EngYorungeSira^ := (sira + 1) and $FFF;
  end;
  if (EngYorungeBas^ = EngYorungeSira^) and MantikOku(PlnTamponBitiyor) then
    FKart.HareketleriBitir;
end;

{ Bir eksende jog başlatır. Sıfırlamada, kart yokken ya da aynı eksenin
  ters yön tuşlarına birlikte basıldığında jog engellenir. }
procedure TCihaz.JogBaslat(eksen, yonKodu: SmallInt; hizOrani: Double);
var
  yeniYon, i: Integer;
  hiz: Double;
begin
  if ProgramBenzetimde then Exit;
  if (eksen >= 0) and (eksen < EKSEN_SAYISI) and (FTusSayisi[eksen] < 4) then Inc(FTusSayisi[eksen]);
  if ProgramSifirlamada then
  begin
    FJogKilidi := True;
    DurumMesaji(MsjSifirlamadaJogYok);
    Exit;
  end;
  if not FKart.Kurulu then
  begin
    FJogKilidi := True;
    DurumMesaji(MsjKartBagliDegil);
    Exit;
  end;
  if (eksen < 0) or (eksen >= EKSEN_SAYISI) then Exit;
  if FJogKilidi then Exit;
  if yonKodu = JOG_ARTI_YON then yeniYon := 1 else yeniYon := -1;
  if FJogEtkin[eksen] and (FJogYonu[eksen] <> yeniYon) then
  begin
    FJogKilidi := True;
    TumJoguDurdur;
    DurumMesaji(MsjTersTuslar, MESAJ_TERS_TUS);
    Exit;
  end;
  if (Engine <> nil) and (EngAdres(ENG_JOG_MESGUL)^ <> 0) then Exit;
  if EngYorungeBas^ <> EngYorungeSira^ then Exit;
  if TEK_EKSEN_JOG then
  begin
    for i := 0 to EKSEN_SAYISI - 1 do
      if (i <> eksen) and FJogEtkin[i] then Exit;
  end;
  if (hizOrani <= 0) or IsNan(hizOrani) then hizOrani := 1.0;
  if hizOrani > 1.0 then hizOrani := hizOrani / 100.0;
  hiz := hizOrani * PlnHiz(eksen)^ * PlnAdimBirimi(eksen)^ / JOG_HIZ_BOLENI;
  if IsNan(hiz) or IsInfinite(hiz) or (hiz < 1.0) then
    hiz := JOG_YEDEK_HIZ * hizOrani;
  FJogYonu[eksen] := yeniYon;
  FJogHizi[eksen] := hiz;
  FJogYorungeIzi := FYorungeSayac;
  FJogEtkin[eksen] := True;
  { Mach3'e harici aygıtın hareket ettiğini bildir: jog bitip konum eşitlenene
    kadar Mach3 aygıtı "meşgul" görür. }
  if MainPlanner <> nil then MantikYaz(PlnHariciDuruyor, False);
  JogZamanlayiciBaslat;
  JogHesapla;
end;

procedure TCihaz.JogZamanlayiciBaslat;
begin
  if gJogZamanlayici = 0 then
  begin
    gJogZamanlayici := api_SetTimer(0, 0, JOG_ZAMANLAYICI_MS, @JogZamanlayiciYordami);
    FJogVurusZamani := SaatMs64;
  end;
  FKart.HizliJog := gJogZamanlayici <> 0;
end;

procedure TCihaz.JogZamanlayiciDurdur;
begin
  if gJogZamanlayici <> 0 then
  begin
    api_KillTimer(0, gJogZamanlayici);
    gJogZamanlayici := 0;
  end;
  if FKart <> nil then FKart.HizliJog := False;
end;

procedure TCihaz.JogVurusu;
var
  basiliVar: Boolean;
  i: Integer;
begin
  FJogVurusZamani := SaatMs64;
  if ProgramBenzetimde or ProgramSifirlamada then
  begin
    JogZamanlayiciDurdur;
    Exit;
  end;
  OdagiDenetle;
  JogTusuDenetle;
  basiliVar := False;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then basiliVar := True;
  if basiliVar then JogHesapla
  else FKart.JogHizmeti;
  { Mach3'e devir (sync) burada YAPILMAZ: son adım sayısı Mach3'e yalnızca
    Guncelle içinde yazılır. Devir de orada, yazmadan hemen sonra yapılır. }
  if (not basiliVar) and (not FKart.JogMesgul) then JogZamanlayiciDurdur;
end;

{ Etkin her eksenin jog hızını geçen süreye karşılık gelen adımlara çevirir. }
procedure TCihaz.JogHesapla;
var
  suAn: QWord;
  dt: Double;
  hareketVar: Boolean;
  i: Integer;
begin
  suAn := SaatMs64;
  dt := (suAn - FSonVurus) / 1000.0;
  FSonVurus := suAn;
  if dt > 0.5 then dt := 0.5;
  if FJogYorungeIzi <> FYorungeSayac then
  begin
    FJogYorungeIzi := FYorungeSayac;
    Exit;
  end;
  hareketVar := False;
  for i := 0 to EKSEN_SAYISI - 1 do
  begin
    if FJogEtkin[i] then
    begin
      FHizlar[i] := FJogYonu[i] * FJogHizi[i];
      hareketVar := True;
    end
    else
      FHizlar[i] := 0;
  end;
  if hareketVar then FKart.JogIlerlet(FHizlar, dt);
end;

{ Jog tuşu bırakıldı: ekseni durdurur ve Mach3 jog bayraklarını temizler. }
procedure TCihaz.JogBitir(eksen: SmallInt);
begin
  if (eksen >= 0) and (eksen < EKSEN_SAYISI) and (FTusSayisi[eksen] > 0) then Dec(FTusSayisi[eksen]);
  if not TusBasiliMi then
  begin
    FJogKilidi := False;
    FOdakKilidi := False;
    DurumMesajiniSil(MESAJ_TERS_TUS);
  end;
  if (eksen < 0) or (eksen > 6) then Exit;
  if eksen < EKSEN_SAYISI then FJogEtkin[eksen] := False;
  if not (FJogEtkin[0] or FJogEtkin[1] or FJogEtkin[2] or FJogEtkin[3]) then
  begin
    FKart.JogDurdur;
    FKart.JogHizmeti;
  end;
  { Bayrakları hemen temizleme: makine yavaşlayıp tamamen durunca temizlenecek. }
  FBayrakBekliyor[eksen] := True;
end;

{ Jog tuşu basılı mı, makine hâlâ jog'dan yavaşlıyor mu ya da Mach3'e
  "jog bitti" henüz bildirilmedi mi? }
function TCihaz.JogDevamEdiyor: Boolean;
var
  i: Integer;
begin
  Result := True;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then Exit;
  for i := 0 to 6 do
    if FBayrakBekliyor[i] then Exit;
  if FKart.JogMesgul then Exit;
  Result := False;
end;

{ Bekleyen jog bayraklarını, jog tamamen bitince (ya da hemen = True ise şimdi)
  temizler. Böylece Mach3 konumu yavaşlama adımları da atıldıktan sonra eşitler. }
procedure TCihaz.BekleyenBayraklariTemizle(hemen: Boolean);
var
  i: Integer;
  bekleyen: Boolean;
begin
  bekleyen := False;
  for i := 0 to 6 do
    if FBayrakBekliyor[i] then bekleyen := True;
  if not bekleyen then Exit;
  if not hemen then
  begin
    for i := 0 to EKSEN_SAYISI - 1 do
      if FJogEtkin[i] then Exit;      { başka eksen hâlâ jog'da }
    if not FKart.HareketDurdu then Exit;
  end;
  for i := 0 to 6 do
    if FBayrakBekliyor[i] then
    begin
      FBayrakBekliyor[i] := False;
      JogBayraklariniSil(i);
    end;
  { Jog bitti ve konum eşitlendi: harici aygıt artık duruyor. }
  FAnaProgram.GkodBitti;
end;

{ Mach3'e eksenin jog'u bitirdiğini bildirir. }
procedure TCihaz.JogBayraklariniSil(eksen: Integer);
var
  sayac, x: Integer;
begin
  MantikYaz(EngEksenYavaslama(eksen), True);
  MantikYaz(EngEksenJog(eksen), False);
  sayac := 0;
  for x := 0 to 5 do
    if not MantikOku(EngEksenJog(x)) then Inc(sayac);
  if sayac >= 6 then
  begin
    MantikYaz(EngJogEtkin, False);
    MantikYaz(PlnJogEtkin, False);
    MantikYaz(EngEsitle, True);
  end;
end;

{ Güvenlik: jog sırasında Mach3 klavye odağını kaybederse tüm jog durur
  (tuş bırakma olayı hiç gelmeyecektir). }
procedure TCihaz.OdagiDenetle;
var
  jogEtkin: Boolean;
  i: Integer;
begin
  if ProgramOnPlanda then
  begin
    if FOdakKilidi and (not KlavyeTusuBasili) then
    begin
      FOdakKilidi := False;
      FJogKilidi := False;
      DurumMesajiniSil(MESAJ_TERS_TUS);
    end;
    Exit;
  end;
  jogEtkin := TusBasiliMi;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then jogEtkin := True;
  if not jogEtkin then Exit;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then FBayrakBekliyor[i] := True;   { devir makine durunca, Guncelle içinde }
  TumJoguDurdur;
  FKart.JogHizmeti;
  FillChar(FTusSayisi, SizeOf(FTusSayisi), 0);
  FJogKilidi := True;
  FOdakKilidi := True;
end;

procedure TCihaz.TumJoguDurdur;
var
  i: Integer;
begin
  for i := 0 to EKSEN_SAYISI - 1 do FJogEtkin[i] := False;
  FKart.JogDurdur;
end;

function TCihaz.TusBasiliMi: Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FTusSayisi[i] > 0 then Exit(True);
end;

{ G4 bekleme başlatır. Mach3 süreyi saniye ya da milisaniye olarak verebilir. }
procedure TCihaz.Bekle(time: Double);
var
  ms: Double;
begin
  if (Engine = nil) or (MainPlanner = nil) then Exit;
  ms := time;
  if PlnAdres(PLN_BEKLEME_MS)^ = 0 then ms := ms * 1000.0;
  if (ms < 0) or IsNan(ms) then ms := 0;
  if ms > 4294967295.0 then ms := 4294967295.0;
  FBeklemeMs := QWord(Trunc(ms));
  FBeklemeBaslangic := SaatMs64;
  FBeklemeEtkin := True;
  PLongInt(EngAdres(ENG_BEKLEME_BAYRAGI))^ := 1;
end;

procedure TCihaz.BeklemeHizmeti;
begin
  if not FBeklemeEtkin then Exit;
  if SaatMs64 - FBeklemeBaslangic > FBeklemeMs then
  begin
    FBeklemeEtkin := False;
    PLongInt(EngAdres(ENG_BEKLEME_BAYRAGI))^ := 0;
  end;
end;

function TCihaz.IslemSuruyor: Boolean;
begin
  Result := FBeklemeEtkin or FJogEtkin[0] or FJogEtkin[1] or FJogEtkin[2] or FJogEtkin[3];
end;

{ G31 prob isteği: probun etkin ve makinenin hazır olduğunu denetler. }
procedure TCihaz.ProbIstegi;
begin
  if Engine = nil then Exit;
  if EngAdres(ENG_PROB_ACIK)^ = 0 then
  begin
    DurumMesaji(MsjProbEtkinDegil);
    PLongInt(EngAdres(ENG_PROB_DURUMU))^ := 0;
    if MainPlanner <> nil then PLongInt(PlnAdres(PLN_PROB_BAYRAGI))^ := 0;
    Exit;
  end;
  if ProgramBenzetimde then Exit;
  if ProgramSifirlamada then
  begin
    DurumMesaji(MsjSifirlamadaProbYok);
    Exit;
  end;
  if IslemSuruyor then
    DurumMesaji(MsjProbBekle);
  { Prob hareketinin kendisi bu sürümde kart tarafından yürütülmez. }
end;

procedure TCihaz.ReferansaGit(eksen: SmallInt);
begin
  { Referansa gitme bu sürümde kart tarafından yürütülmez. }
end;

{ Etkin tüm eksenlerde jog'u durdurur; Mach3'e devir makine durunca Guncelle içinde yapılır. }
procedure TCihaz.JoguKes;
var
  i: Integer;
begin
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then
    begin
      FJogEtkin[i] := False;
      FBayrakBekliyor[i] := True;
    end;
  FKart.JogDurdur;
  FKart.JogHizmeti;
  FillChar(FTusSayisi, SizeOf(FTusSayisi), 0);
end;

{ Jog sırasında pencere çerçevesine tıklandı (bkz. MenuKancasi). Jog yavaşlatılarak
  durdurulur ve ters tuşlarda olduğu gibi tüm jog tuşları bırakılana kadar kilitli kalır.
  Jog tuşu basılıyken ya da jog sürerken True döner; tıklama o zaman yok sayılır. }
function TCihaz.PencereEtkilesimi: Boolean;
var
  i: Integer;
  jogEtkin: Boolean;
begin
  jogEtkin := False;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then jogEtkin := True;
  Result := jogEtkin or FKart.JogMesgul or TusBasiliMi;
  if not (jogEtkin or FKart.JogMesgul) then Exit;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then
    begin
      FJogEtkin[i] := False;
      FBayrakBekliyor[i] := True;
    end;
  FKart.JogDurdur;
  FKart.JogDurusRampasi;
  if jogEtkin then
  begin
    FJogKilidi := True;
    DurumMesaji(MsjPencereJogDurdu, MESAJ_TERS_TUS);
  end;
end;

{ Pencere taşınırken ya da boyutlandırılırken çağrılır. Bir klavye tuşu basılıysa
  jog'u durdurur, tüm tuşlar bırakılana kadar kilitler ve taşıma iptal edilsin
  diye True döner. }
function TCihaz.TasimadaTusDenetle: Boolean;
begin
  Result := KlavyeTusuBasili;
  if not Result then Exit;
  PencereEtkilesimi;
  if not FJogKilidi then
  begin
    FJogKilidi := True;
    DurumMesaji(MsjTasimadaTus, MESAJ_TERS_TUS);
  end;
end;

{ Bir metin kutusu (MDI, DRO) odaktayken basılan jog tuşu, Mach3'ü eşleşen
  JogOn / JogOff olmadan "jog yapıyor" durumunda bırakabilir; Mach3 de
  sonra her yeni jog'u reddeder. Hiçbir jog çalışmazken Mach3 hâlâ jog
  bildiriyorsa, makine duruyorsa ve 200 ms boyunca hiçbir tuş ya da fare
  düğmesi basılı değilse Mach3 jog durumu, sıfırlamanın yapacağı gibi temizlenir. }
procedure TCihaz.TakiliJogDenetle;
const
  TAKILI_JOG_MS = 200;
var
  i: Integer;
  takili: Boolean;
  simdi: QWord;
begin
  if Engine = nil then Exit;
  takili := MantikOku(EngJogEtkin);
  for i := 0 to 5 do
    if MantikOku(EngEksenJog(i)) then takili := True;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then takili := False;
  for i := 0 to 6 do
    if FBayrakBekliyor[i] then takili := False;
  if takili then
    if FKart.JogMesgul or (not FKart.HareketDurdu) or (EngYorungeBas^ <> EngYorungeSira^) or
       KlavyeTusuBasili or (GetAsyncKeyState(VK_LBUTTON) < 0) then takili := False;
  if not takili then
  begin
    FTakiliZamani := 0;
    Exit;
  end;
  simdi := SaatMs64;
  if FTakiliZamani = 0 then
  begin
    FTakiliZamani := simdi;
    Exit;
  end;
  if simdi - FTakiliZamani < TAKILI_JOG_MS then Exit;
  FTakiliZamani := 0;
  for i := 0 to 5 do
    if MantikOku(EngEksenJog(i)) then JogBayraklariniSil(i);
  if MantikOku(EngJogEtkin) then
  begin
    MantikYaz(EngJogEtkin, False);
    MantikYaz(PlnJogEtkin, False);
    MantikYaz(EngEsitle, True);
  end;
  FAnaProgram.GkodBitti;
end;

{ GÜVENLİK: Jog'u yalnızca Mach3'ün JogOff haberine bağlı bırakma. Mach3 bazı
  durumlarda (ör. jog sırasında Goto Zero) JogOff göndermez ve makine sonsuza
  kadar gider. Jog etkinken hiçbir klavye tuşu ve fare düğmesi 30 ms boyunca
  basılı değilse jog durdurulur. }
procedure TCihaz.JogTusuDenetle;
const
  TUS_YOK_MS = 30;
var
  i: Integer;
  aktif, basili: Boolean;
  simdi: QWord;
begin
  aktif := False;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then aktif := True;
  if not aktif then
  begin
    FTusYokZamani := 0;
    Exit;
  end;
  basili := KlavyeTusuBasili or (GetAsyncKeyState(VK_LBUTTON) < 0) or
    (GetAsyncKeyState(VK_RBUTTON) < 0) or (GetAsyncKeyState(VK_MBUTTON) < 0);
  if basili then
  begin
    FTusYokZamani := 0;
    Exit;
  end;
  simdi := SaatMs64;
  if FTusYokZamani = 0 then
  begin
    FTusYokZamani := simdi;
    Exit;
  end;
  if simdi - FTusYokZamani < TUS_YOK_MS then Exit;
  FTusYokZamani := 0;
  JoguKes;
end;

{ Jog kilidi normalde her JogOn'a karşılık bir JogOff gelince açılır. Ama Mach3
  bazı durumlarda (ör. tuş basılıyken Goto Zero başlatılınca) JogOff göndermez;
  sayaç sıfıra inmez ve kilit sonsuza kadar kalır. Bu yüzden gerçek klavye ve
  fare durumuna da bakılır: hiçbir tuş basılı değilse kilit ve sayaçlar sıfırlanır. }
procedure TCihaz.KilidiDenetle;
var
  i: Integer;
begin
  if not (FJogKilidi or FOdakKilidi or TusBasiliMi) then Exit;
  if not ProgramOnPlanda then Exit;          { odak yokken OdagiDenetle yönetir }
  if KlavyeTusuBasili then Exit;
  if (GetAsyncKeyState(VK_LBUTTON) < 0) or (GetAsyncKeyState(VK_RBUTTON) < 0) or
     (GetAsyncKeyState(VK_MBUTTON) < 0) then Exit;   { ekrandaki jog düğmesi fareyle tutuluyor olabilir }
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogEtkin[i] then Exit;
  FillChar(FTusSayisi, SizeOf(FTusSayisi), 0);
  FJogKilidi := False;
  FOdakKilidi := False;
  DurumMesajiniSil(MESAJ_TERS_TUS);
end;

{ Mach3'ün yarıda kalan hareketi atması için çağırdığı Purge (Stop / acil stop). }
procedure TCihaz.Temizle(flags: SmallInt);
begin
  HareketiTemizle;
end;

{ Yarıda kesilen hareketin izlerini temizler:
  1. kart katmanındaki G-kod durumunu sıfırlar,
  2. Mach3 yörünge tamponunda kalan noktaları atar (TrajIndex := TrajHead),
  3. Mach3'e harici aygıtın durduğunu bildirir (ExternalStill := True).
  Bu yapılmazsa acil stop'tan sonra Mach3 eski hareketin bitmesini bekler
  ve yeni hareket (ör. Goto Zero) başlamaz. }
procedure TCihaz.HareketiTemizle;
begin
  FKart.Temizle;
  if Engine <> nil then EngYorungeSira^ := EngYorungeBas^;
  FAnaProgram.GkodBitti;
end;

{ Mach3 Reset düğmesi: jog ve beklemeyi durdurur, sonra kartı kurar ya da çözer. }
procedure TCihaz.Sifirla;
begin
  TumJoguDurdur;
  if TusBasiliMi then FJogKilidi := True;
  if FBeklemeEtkin then
  begin
    FBeklemeEtkin := False;
    if Engine <> nil then PLongInt(EngAdres(ENG_BEKLEME_BAYRAGI))^ := 0;
  end;
  FKart.BaglantiyiDegistir;
end;

end.
