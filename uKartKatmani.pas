{
 ============================================================================
  SafCNC - SafCNC denetleyici kartları (Arduino Uno / Nano) için Mach3 hareket eklentisi
 ----------------------------------------------------------------------------
  Dosya         : uKartKatmani.pas - Mach3 ile seri bağlantı arasındaki mantık katmanı
  Geliştirici   : Fikret Palas
  E-posta       : safcnc@tutamail.com
  Web           : https://github.com/fikretpalas
  Kart yazılımı : https://github.com/fikretpalas/SafCNC_Arduino
  Lisans        : MIT
  Sürüm         : 1.0.0
  Kartlar       : Arduino Uno / Nano (yaklaşık 30 kHz); STM32 ile 100 kHz'e kadar (test edilmedi)
 ============================================================================
  Bağlantı durumu, konum sayma, G-kod ve jog dilimleri, çıkışlar, kart
  alarmları ve durum penceresinde gösterilen veriler.
}
unit uKartKatmani;

{$mode objfpc}{$H+}
{$codepage utf8}
{$R-}{$Q-}

interface

uses
  Windows, SysUtils, Math, uSistemApi, uMesajlar, uKartProtokol, uAnaProgram,
  uSeriBaglanti, uKartPenceresi;

const
  HARICI_TAMPON_UST = 200;
  TAMPON_PAKET = 40;
  GUNCELLEME_BASINA_DILIM = 100;
  JOG_TAMPON_PAKET = 14;
  JOG_DURUS_PAKET = 180;
  BITIS_BEKLEME_MS = 300;
  KART_BEKLEME_MS = 3000;
  KART_ARAMA_MS = 8000;
  BAGLANTI_MESAJ_MS = 3000;
  ALARMDA_SIFIRLA = True;
  MIL_TERS_YON_ACAR = True;
  BOSALMA_DENETIMI = True;

type
  TBaglantiDurumu = (bdAraniyor, bdBagli, bdKoptu, bdYok);
  TEksenReal = array[0..EKSEN_SAYISI - 1] of Double;
  TEksenAdim = array[0..EKSEN_SAYISI - 1] of LongInt;

  TKartKatmani = class
  private
    FAnaProgram: TAnaProgram;
    FPort: TSeriBaglanti;
    FDilimSuresi: Double;
    FAdimlar: TEksenAdim;
    FIstenen: TEksenReal;
    FSonYazilan: TEksenAdim;
    FKurulu: Boolean;
    FKurulumIstegi: Boolean;
    FBekliyor: Boolean;
    FBeklemeBasi: DWord;
    FBaglantiDurumu: TBaglantiDurumu;
    FAramaBaslangic: DWord;
    FPortNo: DWord;
    FJogCalisiyor: Boolean;
    FJogDuruyor: Boolean;
    FJogAnlikHiz: TEksenReal;
    FJogBaslangic: DWord;
    FJogGonderilen: Integer;
    FGkodEtkin: Boolean;
    FBitisBekliyor: Boolean;
    FBitisZamani: DWord;
    FAzamiOnde: Integer;
    FGuncellemeBasina: Integer;
    FCikis: Byte;
    FMil: Byte;
    FYollananCikis: Byte;
    FYollananMil: Byte;
    FKartDurumu: TKartDurumu;
    FKartDurumNo: DWord;
    FDilimArtis: TEksenReal;
    FDilimAdim: TEksenAdim;
    FJogArtis: TEksenReal;
    FHizliJog: Boolean;
    FSonDilimDurumNo: DWord;
    FSonDilimDurum: TKartDurumu;
    FBilgiNo: DWord;
    FAzamiAdimHz: Integer;
    FKartSinirlari: TKartSinirlari;
    FKartBilgisiVar: Boolean;

    function Sifirlamada: Boolean;
    function HareketUygun: Boolean;
    function KartHareketli: Boolean;
    function PencereBilgisi: TKartBilgisi;
    function JogIvmesi(eksen: Integer): Double;
    function BosalmaGuvenli: Boolean;
    function DenetimBitleri: Byte;
    procedure CikislariYenile;
    procedure CikislariGonder;
    procedure CikislariEsitle;
    procedure CekirdegiAyarla(adimHz: Integer);
    procedure KartBilgisiniDenetle;
    function HizlarUygun(uyar: Boolean): Boolean;
    procedure KurmayiDene;
    procedure BaglantiyiDenetle;
    procedure AramayiBaslat(const mesajMetni: UnicodeString);
    procedure BaglantiMesajlari;
    procedure BaglantiyiBirak(neden: Byte);
    procedure SifirlamayaGir(sebep: Integer);
    procedure SifirlamaDugmesineBas;
    procedure KartAlarminiDenetle;
    procedure DurusuUygula;
    function DilimUygula(const d: array of Double): Boolean;
    procedure JogSifirla;
    procedure SonrakiJogHizi(const hizlar: array of Double);
    procedure JogYurut(const hizlar: array of Double);
    procedure JogDurusHizmeti;
    function ArtikAdimVar: Boolean;
  public
    constructor Create(AAnaProgram: TAnaProgram);
    destructor Destroy; override;

    procedure PencereyiGoster(sahip: HWND);
    procedure PencereyiGuncelle;
    procedure PencereyiBirak;
    procedure Baslat;
    procedure Sonlandir;
    procedure BaglantiyiDegistir;
    function KabulEdebilir: Boolean;
    procedure GkodDilimi(const adimSayisi: array of Double);
    procedure HareketleriBitir;
    procedure Temizle;
    procedure JogIlerlet(const hizlar: array of Double; dt: Double);
    procedure JogHizmeti;
    function JogMesgul: Boolean;
    function HareketDurdu: Boolean;
    procedure JogDurdur;
    procedure JogDurusRampasi;
    procedure KonumuGuncelle;

    property Kurulu: Boolean read FKurulu;
    property HizliJog: Boolean read FHizliJog write FHizliJog;
  end;

implementation

const
  SIFIR: TEksenReal = (0, 0, 0, 0);

function KonumYuvarla(d: Double; varsayilan: Integer): Integer;
begin
  if IsNan(d) or IsInfinite(d) or (d > 2147483646.0) or (d < -2147483647.0) then
    Exit(varsayilan);
  Result := Floor(d + 0.5);
end;

function ZamanDamgasi: DWord;
begin
  Result := DWord(SaatMs64 and $FFFFFFFF);
end;

{ İki DWord zaman damgası arasındaki işaretli fark (taşmaya dayanıklı). }
function Gecen(simdi, once: DWord): LongInt;
begin
  Result := LongInt(DWord(simdi - once));
end;

constructor TKartKatmani.Create(AAnaProgram: TAnaProgram);
begin
  inherited Create;
  FAnaProgram := AAnaProgram;
  FDilimSuresi := UNO_DILIM_SN;
  FAzamiOnde := TAMPON_PAKET;
  FPort := TSeriBaglanti.Create;
end;

destructor TKartKatmani.Destroy;
begin
  FPort.Free;
  inherited Destroy;
end;

function TKartKatmani.Sifirlamada: Boolean;
begin
  Result := FAnaProgram.Sifirlamada;
end;

function TKartKatmani.HareketUygun: Boolean;
begin
  Result := FPort.HareketeHazir;
end;

function TKartKatmani.KartHareketli: Boolean;
var
  d: TKartDurumu;
begin
  FPort.DurumAl(d);
  Result := d.Durum = K_HAREKET;
end;

procedure TKartKatmani.PencereyiGoster(sahip: HWND);
begin
  KartPenceresiGoster(sahip, @PencereBilgisi);
end;

procedure TKartKatmani.PencereyiGuncelle;
begin
  KartPenceresiGuncelle;
end;

procedure TKartKatmani.PencereyiBirak;
begin
  KartPenceresiSerbest;
end;

function TKartKatmani.PencereBilgisi: TKartBilgisi;
begin
  Result.Kurulu := FKurulu;
  Result.Mevcut := FPort.Goruldu;
  Result.PortAdi := FPort.PortAdi;
  Result.Baud := UNO_BAUD;
  Result.GeriBildirimVar := FPort.Goruldu and (FKartDurumNo <> 0);
  Result.Lamba := DurumLambaKodu(FKartDurumu.Durum);
end;

function TKartKatmani.JogIvmesi(eksen: Integer): Double;
var
  a, s: Double;
begin
  a := FAnaProgram.Ivme(eksen);
  s := FAnaProgram.AdimBirimi(eksen);
  if IsNan(a) or IsInfinite(a) or IsNan(s) or IsInfinite(s) then Exit(0);
  if (a > 0) and (s > 0) then Result := a * s else Result := 0;
end;

{ Hareket yeterince yavaşsa kısa bir USB gecikmesi tampon boşalmasına yol açamaz. }
function TKartKatmani.BosalmaGuvenli: Boolean;
var
  bilinen, i: Integer;
  a: Double;
begin
  bilinen := 0;
  for i := 0 to UNO_EKSEN - 1 do
  begin
    a := JogIvmesi(i);
    if a <= 0 then Continue;
    if a * FDilimSuresi * FDilimSuresi > UNO_HIZLI_DILIM / 2.0 then Exit(False);
    Inc(bilinen);
  end;
  Result := bilinen > 0;
end;

function TKartKatmani.DenetimBitleri: Byte;
begin
  Result := 0;
  if FAnaProgram.LimitDurdurur then Result := Result or C_LIMITDUR;
  if BOSALMA_DENETIMI and FGkodEtkin and BosalmaGuvenli then Result := Result or C_BOSALMA;
end;

procedure TKartKatmani.CikislariYenile;
var
  kapsanan, m: Byte;
begin
  m := FAnaProgram.CikisMaskesi(kapsanan);
  m := m and kapsanan and C_CIKISLAR;
  if MIL_TERS_YON_ACAR and ((m and C_MIL_YON) <> 0) then m := m or C_MIL_ACIK;
  if Sifirlamada then m := 0
  else m := m or DenetimBitleri;
  FCikis := m;
  FMil := FAnaProgram.MilGucu;
end;

procedure TKartKatmani.CikislariGonder;
begin
  FPort.CikislariAyarla(FMil, FCikis);
  FYollananCikis := FCikis;
  FYollananMil := FMil;
end;

procedure TKartKatmani.CikislariEsitle;
begin
  if (not FKurulu) or (not FPort.Bagli) then Exit;
  if (FCikis <> FYollananCikis) or (FMil <> FYollananMil) then CikislariGonder;
end;

{ Mach3'e en yüksek adım hızını (darbe hızı) bildirir; Mach3 eksen hızlarını
  buna göre sınırlar. }
procedure TKartKatmani.CekirdegiAyarla(adimHz: Integer);
var
  khz: Integer;
begin
  FAzamiAdimHz := adimHz;
  khz := adimHz div 1000;
  if khz < 1 then khz := 1;
  FAnaProgram.SurucuyuAyarla(khz, HARICI_TAMPON_UST, UNO_DILIM_SN);
end;

{ Kart bağlı değilken Mach3'e protokolün tavanı (100 kHz) bildirilir; Motor
  Tuning'de hız buna kadar ayarlanabilir. Kart bağlanıp K_BILGI ile kendi
  sınırını bildirince Mach3'e o sınır bildirilir ve eksen hızları denetlenir.
  Dilimlerdeki adım sınırı (KartAdimAzami) her zaman son bilinen kart
  değerinde kalır. Mach3 sürücü ayarı yalnızca değer değişince yazılır. }
procedure TKartKatmani.KartBilgisiniDenetle;
var
  bilgi: TKartSinirlari;
  no: DWord;
  degisti: Boolean;
begin
  no := FPort.BilgiAl(bilgi);
  if no = FBilgiNo then
  begin
    if not FPort.Goruldu then
    begin
      FKartBilgisiVar := False;
      if FAzamiAdimHz <> UNO_TAVAN_HZ then CekirdegiAyarla(UNO_TAVAN_HZ);
    end;
    Exit;
  end;
  FBilgiNo := no;
  KartBilgisiUygula(bilgi);
  if not bilgi.KarttanGeldi then Exit;
  FKartSinirlari := bilgi;
  FKartBilgisiVar := True;
  degisti := bilgi.AzamiAdimHz <> FAzamiAdimHz;
  if degisti then CekirdegiAyarla(bilgi.AzamiAdimHz);
  if degisti then
    FAnaProgram.MesajGoster(Bicimle(MsjKartHizi,
      [UnicodeString(IntToStr(bilgi.AzamiAdimHz div 1000) + ',' +
                     IntToStr((bilgi.AzamiAdimHz mod 1000) div 100)),
       UnicodeString(IntToStr(bilgi.AdimSiniri))]));
  HizlarUygun(True);
end;

function SayiMetni(v: Double; basamak: Integer): UnicodeString;
begin
  Result := UnicodeString(FloatToStrF(v, ffFixed, 15, basamak));
end;

{ Mach3 eksen hızlarını (Motor Tuning) kartın sınırıyla karşılaştırır.
  Hepsi sınırın içindeyse True döner. Aşan eksen varsa False döner; uyar True
  ise (pencere zaten açık değilse) her eksenin hızını ve izin verilen en
  yüksek hızı gösteren uyarıyı açar. Eklenti Mach3 ayarlarını değiştirmez. }
function TKartKatmani.HizlarUygun(uyar: Boolean): Boolean;
const
  EKSEN_HARFI: array[0..2] of UnicodeString = ('X', 'Y', 'Z');
var
  i: Integer;
  adim, hiz, enFazla: Double;
  satirlar: UnicodeString;
begin
  Result := True;
  if (not FKartBilgisiVar) or (MainPlanner = nil) then Exit;
  satirlar := '';
  for i := 0 to UNO_EKSEN - 1 do
  begin
    adim := Abs(PlnAdimBirimi(i)^);
    hiz := PlnHiz(i)^;
    if IsNan(adim) or IsInfinite(adim) or IsNan(hiz) or IsInfinite(hiz) then Continue;
    if (adim <= 0) or (hiz <= 0) then Continue;
    if hiz * adim <= FKartSinirlari.AzamiAdimHz then Continue;
    Result := False;
    enFazla := Floor(FKartSinirlari.AzamiAdimHz / adim * 60.0 * 100.0) / 100.0;
    satirlar := satirlar + Bicimle(HizUyarisiSatir, [EKSEN_HARFI[i], SayiMetni(hiz * 60.0, 2),
      SayiMetni(hiz * adim / 1000.0, 1), SayiMetni(enFazla, 2)]) + #13#10;
  end;
  if Result or (not uyar) or HizUyarisiAcik then Exit;
  HizUyarisiGoster(Bicimle(HizUyarisiGiris, [SayiMetni(FKartSinirlari.AzamiAdimHz / 1000.0, 1),
    UnicodeString(IntToStr(FKartSinirlari.AdimSiniri))]) + #13#10#13#10 + satirlar + #13#10 + HizUyarisiSon);
end;

procedure TKartKatmani.Baslat;
var
  bilgi: TKartSinirlari;
begin
  FBilgiNo := FPort.BilgiAl(bilgi);
  KartBilgisiUygula(bilgi);
  CekirdegiAyarla(UNO_TAVAN_HZ);
  FKartDurumNo := 0;
  FPort.Hizmet;
  FPortNo := FPort.YeniPortSayisi;
  AramayiBaslat(MsjKartAraniyor);
end;

procedure TKartKatmani.Sonlandir;
begin
  if FPort.Bagli then
  begin
    if FKurulu then
    begin
      FPort.KurulumuSifirla(H_ACILIS);
      FKurulu := False;
      FKurulumIstegi := False;
    end;
    FPort.Bosalt(300);
    FPort.Kapat;
  end;
end;

{ Mach3 sıfırlamadan çıktığında ve kart varsa kartı kurar (bağlantıyı açar). }
procedure TKartKatmani.KurmayiDene;
begin
  if FKurulu or (not FKurulumIstegi) then Exit;
  if not FPort.Goruldu then Exit;
  if Sifirlamada then Exit;
  { Mach3 hızları kartın sınırını aşıyorsa kart bağlanmaz: uyarı açılır ve
    Mach3 sıfırlamaya geri alınır. Her Reset'te yeniden denetlenir. }
  if not HizlarUygun(True) then
  begin
    FAnaProgram.MesajGoster(MsjHizlarYuksek);
    SifirlamayaGir(SIFIRLAMA_NEDENI_KART);
    Exit;
  end;
  FGkodEtkin := False;
  FBitisBekliyor := False;
  CikislariYenile;
  CikislariGonder;
  FPort.KurulumuBaslat;
  FKurulu := True;
end;

{ Mach3 sıfırlamadan çıkmış ama kart kurulamamışsa KART_BEKLEME_MS kadar bekler,
  sonra Mach3'ü yeniden sıfırlamaya alır. }
procedure TKartKatmani.BaglantiyiDenetle;
begin
  if FKurulu or Sifirlamada or (not FAnaProgram.SifirlamaBilgisiVar) then
  begin
    FBekliyor := False;
    Exit;
  end;
  FKurulumIstegi := True;
  if not FBekliyor then
  begin
    FBekliyor := True;
    FBeklemeBasi := ZamanDamgasi;
    Exit;
  end;
  if Gecen(ZamanDamgasi, FBeklemeBasi) < KART_BEKLEME_MS then Exit;
  FBekliyor := False;
  FAnaProgram.MesajGoster(MsjKartYokSifirlama);
  SifirlamayaGir(SIFIRLAMA_NEDENI_BEKCI);
end;

procedure TKartKatmani.AramayiBaslat(const mesajMetni: UnicodeString);
begin
  FBaglantiDurumu := bdAraniyor;
  FAramaBaslangic := ZamanDamgasi;
  FAnaProgram.SureliMesaj(mesajMetni, MESAJ_BAGLANTI, 0);
end;

{ Bağlantı mesajlarını (aranıyor, bağlandı, bulunamadı, koptu) durum satırında gösterir. }
procedure TKartKatmani.BaglantiMesajlari;
var
  yeniPort: Boolean;
begin
  yeniPort := FPort.YeniPortSayisi <> FPortNo;
  FPortNo := FPort.YeniPortSayisi;
  if FPort.Goruldu then
  begin
    if FBaglantiDurumu <> bdBagli then
    begin
      FBaglantiDurumu := bdBagli;
      FAnaProgram.SureliMesaj(MsjKartBaglandi, MESAJ_BAGLANTI, BAGLANTI_MESAJ_MS);
    end;
    Exit;
  end;
  if yeniPort then
  begin
    AramayiBaslat(MsjYeniBaglanti);
    Exit;
  end;
  case FBaglantiDurumu of
    bdBagli:
      begin
        FBaglantiDurumu := bdKoptu;
        FAnaProgram.SureliMesaj(MsjBaglantiKoptu, MESAJ_BAGLANTI, 0);
      end;
    bdAraniyor:
      if Gecen(ZamanDamgasi, FAramaBaslangic) >= KART_ARAMA_MS then
      begin
        FBaglantiDurumu := bdYok;
        FAnaProgram.SureliMesaj(MsjKartBulunamadi, MESAJ_BAGLANTI, 0);
      end;
  end;
end;

{ Mach3 Reset düğmesi: kartı bağlar ya da bağlantıyı keser. }
procedure TKartKatmani.BaglantiyiDegistir;
var
  baglanmakIster: Boolean;
begin
  if FAnaProgram.SifirlamaBilgisiVar then
    baglanmakIster := not Sifirlamada
  else
    baglanmakIster := not (FKurulu or FKurulumIstegi);
  if baglanmakIster then
  begin
    FKurulumIstegi := True;
    FPort.Hizmet;
    KurmayiDene;
  end
  else
    BaglantiyiBirak(H_ACILIS);
end;

procedure TKartKatmani.BaglantiyiBirak(neden: Byte);
var
  i: Integer;
begin
  if FPort.Bagli then FPort.KurulumuSifirla(neden);
  FKurulu := False;
  FKurulumIstegi := False;
  JogSifirla;
  FGkodEtkin := False;
  FBitisBekliyor := False;
  FYollananCikis := 0;
  FYollananMil := 0;
  for i := 0 to EKSEN_SAYISI - 1 do FIstenen[i] := FAdimlar[i];
end;

procedure TKartKatmani.SifirlamayaGir(sebep: Integer);
begin
  if FAnaProgram.SifirlamaBilgisiVar then
  begin
    FAnaProgram.SifirlamayaAl(sebep);
    BaglantiyiBirak(H_ACILSTOP);
  end
  else
  begin
    BaglantiyiBirak(H_ACILSTOP);
    SifirlamaDugmesineBas;
  end;
end;

procedure TKartKatmani.SifirlamaDugmesineBas;
begin
  if Sifirlamada then Exit;
  FAnaProgram.SifirlamaDugmesineBas;
end;

{ Kartın ya da bağlantının bildirdiği hataları işler: nedenini gösterir
  ve Mach3'ü sıfırlamaya alır. }
procedure TKartKatmani.KartAlarminiDenetle;
var
  h, kaynak: Byte;
  hataVar: Boolean;
  sebep: Integer;
begin
  hataVar := FPort.HataAl(h, kaynak);
  if (not hataVar) and FKurulu and (not FPort.Bagli) then
  begin
    hataVar := True;
    h := H_ZAMANASIMI;
    kaynak := HK_PC;
  end;
  if (not hataVar) or (not FKurulu) then Exit;
  if Sifirlamada then
  begin
    BaglantiyiBirak(h);
    Exit;
  end;
  FAnaProgram.MesajGoster(KartSifirlamaMesaji(h, kaynak = HK_KART));
  if not ALARMDA_SIFIRLA then
  begin
    BaglantiyiBirak(h);
    FKurulumIstegi := True;
    Exit;
  end;
  case h of
    H_ACILIS, H_ZAMANASIMI: sebep := SIFIRLAMA_NEDENI_BEKCI;
  else
    sebep := SIFIRLAMA_NEDENI_KART;
  end;
  SifirlamayaGir(sebep);
end;

{ Bir duruştan sonra kartın yürütmediği adımlarla konumu düzeltir. }
procedure TKartKatmani.DurusuUygula;
var
  fark: TEksenTam;
  belirsiz: Boolean;
  i: Integer;
begin
  if not FPort.DurusAl(fark, belirsiz) then Exit;
  for i := 0 to UNO_EKSEN - 1 do
  begin
    FAdimlar[i] := FAdimlar[i] - fark[i];
    FIstenen[i] := FIstenen[i] - fark[i];
  end;
  if belirsiz then FAnaProgram.MesajGoster(MsjKonumBelirsiz);
end;

function TKartKatmani.KabulEdebilir: Boolean;
begin
  Result := FKurulu and HareketUygun and (FPort.Derinlik < FAzamiOnde) and
    (FGuncellemeBasina < GUNCELLEME_BASINA_DILIM);
end;

{ Planlanan hareketin bir dilimini eksen başına tam adıma çevirip gönderir.
  Kesirler saklanır; böylece zamanla adım kaybolmaz. }
function TKartKatmani.DilimUygula(const d: array of Double): Boolean;
var
  i, adimSayisi: Integer;
  artis: Double;
begin
  Result := False;
  if not FKurulu then Exit;
  for i := 0 to EKSEN_SAYISI - 1 do
  begin
    if i <= High(d) then artis := d[i] else artis := 0;
    if IsNan(artis) or IsInfinite(artis) then artis := 0;
    FDilimArtis[i] := artis;
    adimSayisi := KonumYuvarla(FIstenen[i] + artis, FAdimlar[i]) - FAdimlar[i];
    if i < UNO_EKSEN then
    begin
      if adimSayisi > KartAdimAzami then adimSayisi := KartAdimAzami
      else if adimSayisi < -KartAdimAzami then adimSayisi := -KartAdimAzami;
    end;
    FDilimAdim[i] := adimSayisi;
  end;
  if not FPort.DilimGonder(FDilimAdim[0], FDilimAdim[1], FDilimAdim[2]) then
  begin
    for i := 0 to EKSEN_SAYISI - 1 do FIstenen[i] := FAdimlar[i];
    Exit;
  end;
  Inc(FGuncellemeBasina);
  FSonDilimDurumNo := FPort.DurumAl(FSonDilimDurum);
  for i := 0 to EKSEN_SAYISI - 1 do
  begin
    FIstenen[i] := FIstenen[i] + FDilimArtis[i];
    FAdimlar[i] := FAdimlar[i] + FDilimAdim[i];
  end;
  Result := True;
end;

procedure TKartKatmani.GkodDilimi(const adimSayisi: array of Double);
begin
  if Sifirlamada or (not FKurulu) then Exit;
  FGkodEtkin := True;
  FBitisBekliyor := False;
  DilimUygula(adimSayisi);
end;

{ İstenen konum ile gerçekte gönderilen adım sayısı arasında tam adımlık fark var mı? }
function TKartKatmani.ArtikAdimVar: Boolean;
var
  i: Integer;
begin
  Result := False;
  for i := 0 to UNO_EKSEN - 1 do
    if KonumYuvarla(FIstenen[i], FAdimlar[i]) <> FAdimlar[i] then Exit(True);
end;

{ Kart son hareketleri bitirene kadar bekler, sonra Mach3'e programın bittiğini bildirir. }
procedure TKartKatmani.HareketleriBitir;
begin
  if FKurulu and FGkodEtkin then
  begin
    { Son dilimlerde adım sınırına (KartAdimAzami) takılıp gönderilemeyen
      artık adımlar varsa, hareketi bitirmeden önce onları da gönder.
      Yoksa makine hedefin bir-iki adım gerisinde kalır. }
    if ArtikAdimVar then
    begin
      if KabulEdebilir then DilimUygula(SIFIR);
      FBitisBekliyor := False;
      Exit;
    end;
    if FPort.Bagli then
    begin
      if FPort.Derinlik > 0 then
      begin
        FBitisBekliyor := False;
        Exit;
      end;
      if not FBitisBekliyor then
      begin
        FBitisBekliyor := True;
        FBitisZamani := ZamanDamgasi;
      end;
      if KartHareketli and (Gecen(ZamanDamgasi, FBitisZamani) < BITIS_BEKLEME_MS) then Exit;
    end;
    FGkodEtkin := False;
    FBitisBekliyor := False;
  end;
  FAnaProgram.GkodBitti;
end;

{ Yarıda kesilen G-kod hareketini bırakır: hareket durumunu kapatır ve
  kesirli istenen konumu gerçekte atılmış adımlara eşitler. }
procedure TKartKatmani.Temizle;
var
  i: Integer;
begin
  FGkodEtkin := False;
  FBitisBekliyor := False;
  for i := 0 to EKSEN_SAYISI - 1 do FIstenen[i] := FAdimlar[i];
end;

procedure TKartKatmani.JogSifirla;
var
  i: Integer;
begin
  FJogCalisiyor := False;
  FJogDuruyor := False;
  FillChar(FJogAnlikHiz, SizeOf(FJogAnlikHiz), 0);
  { Jog bitti: kesirli istenen konumu atılan adımlara eşitle. Mach3 bundan sonraki
    hareketi tam adım konumundan (DRO) planlar; kesir kalırsa yuvarlama 1 adım kaydırabilir. }
  for i := 0 to EKSEN_SAYISI - 1 do FIstenen[i] := FAdimlar[i];
end;

{ Jog bitti, kartın tamponu boşaldı ve kart hareket etmiyor mu?
  Mach3'e "jog bitti" ancak o zaman söylenmeli; yoksa Mach3 konumu
  yavaşlama adımları bitmeden alır ve sonraki hareket kayar. }
function TKartKatmani.HareketDurdu: Boolean;
var
  d: TKartDurumu;
  no: DWord;
begin
  if JogMesgul then Exit(False);
  if (not FKurulu) or (not FPort.Bagli) then Exit(True);
  if FPort.Derinlik > 0 then Exit(False);
  { Son dilim gönderildikten SONRA en az 2 taze durum paketi gelmiş olmalı
    (her 50 ms'de bir) ve kart "tampon boş, hareket yok" demeli. Eski bir
    durum paketine ya da sadece tampon tahminine güvenme. }
  no := FPort.DurumAl(d);
  if DWord(no - FSonDilimDurumNo) < 2 then Exit(False);
  Result := (d.Durum <> K_HAREKET) and (d.Tampon = 0);
end;

{ Her eksenin jog hızını, eksen ivmesiyle sınırlı olarak bir dilim boyunca
  istenen hıza yaklaştırır ve o dilimin adımlarını hazırlar. }
procedure TKartKatmani.SonrakiJogHizi(const hizlar: array of Double);
var
  azamiHiz, hedef, ivmeDeg, adim: Double;
  i: Integer;
begin
  azamiHiz := (KartAdimAzami - 1) / FDilimSuresi;
  for i := 0 to EKSEN_SAYISI - 1 do
  begin
    if i <= High(hizlar) then hedef := hizlar[i] else hedef := 0;
    if hedef > azamiHiz then hedef := azamiHiz;
    if hedef < -azamiHiz then hedef := -azamiHiz;
    ivmeDeg := JogIvmesi(i);
    if ivmeDeg > 0 then
    begin
      adim := ivmeDeg * FDilimSuresi;
      if FJogAnlikHiz[i] < hedef - adim then FJogAnlikHiz[i] := FJogAnlikHiz[i] + adim
      else if FJogAnlikHiz[i] > hedef + adim then FJogAnlikHiz[i] := FJogAnlikHiz[i] - adim
      else FJogAnlikHiz[i] := hedef;
    end
    else
      FJogAnlikHiz[i] := hedef;
    FJogArtis[i] := FJogAnlikHiz[i] * FDilimSuresi;
  end;
end;

{ İvmeli jog dilimleri üretir; tuş bırakılınca makine çabuk dursun diye
  kart tamponunu kısa tutar. }
procedure TKartKatmani.JogYurut(const hizlar: array of Double);
var
  tampon, hedefDilim: Integer;
begin
  if Sifirlamada or (not FKurulu) then Exit;
  if not FJogCalisiyor then
  begin
    FJogCalisiyor := True;
    FillChar(FJogAnlikHiz, SizeOf(FJogAnlikHiz), 0);
    FJogBaslangic := ZamanDamgasi;
    FJogGonderilen := 0;
  end;
  if not HareketUygun then Exit;
  { Jog sırasında kart tamponu boşaldıysa (örneğin başlık çubuğuna tıklanınca ya da
    pencere sürüklenince Windows Mach3 penceresini bekletir) motorlar zaten
    durmuştur. Rampa sıfırdan yeniden başlatılır; tam hızla devam etmek
    motorları kilitler. }
  if (FJogGonderilen > 0) and (FPort.Derinlik = 0) then
  begin
    FillChar(FJogAnlikHiz, SizeOf(FJogAnlikHiz), 0);
    FJogBaslangic := ZamanDamgasi;
    FJogGonderilen := 0;
  end;
  tampon := FAzamiOnde;
  if FHizliJog and (JOG_TAMPON_PAKET < tampon) then tampon := JOG_TAMPON_PAKET;
  hedefDilim := Trunc(Gecen(ZamanDamgasi, FJogBaslangic) / (FDilimSuresi * 1000.0)) + tampon;
  while (FJogGonderilen < hedefDilim) and (FPort.Derinlik < tampon) and
        (FGuncellemeBasina < GUNCELLEME_BASINA_DILIM) do
  begin
    SonrakiJogHizi(hizlar);
    if not DilimUygula(FJogArtis) then Break;
    Inc(FJogGonderilen);
  end;
end;

{ Yavaşlama rampasının tamamını tek seferde karta gönderir (yaklaşık 0,9 s'ye kadar).
  Windows Mach3 penceresini bekletmek üzereyken kullanılır: kart, sonraki
  dilimler üretilemese bile kendi başına yavaşlayıp durur. Rampa daha
  uzunsa JogHizmeti kalanını sonra tamamlar. }
procedure TKartKatmani.JogDurusRampasi;
var
  hareketli: Boolean;
  i: Integer;
begin
  if not FJogCalisiyor then Exit;
  FJogDuruyor := True;
  if Sifirlamada or (not FKurulu) or (not HareketUygun) then Exit;
  while FPort.Derinlik < JOG_DURUS_PAKET do
  begin
    SonrakiJogHizi(SIFIR);
    hareketli := False;
    for i := 0 to EKSEN_SAYISI - 1 do
      if FJogAnlikHiz[i] <> 0 then hareketli := True;
    if not hareketli then Break;
    if not DilimUygula(FJogArtis) then Break;
    Inc(FJogGonderilen);
  end;
end;

procedure TKartKatmani.JogIlerlet(const hizlar: array of Double; dt: Double);
begin
  FJogDuruyor := False;
  JogYurut(hizlar);
end;

procedure TKartKatmani.JogHizmeti;
begin
  JogDurusHizmeti;
end;

function TKartKatmani.JogMesgul: Boolean;
begin
  Result := FJogCalisiyor or FJogDuruyor;
end;

procedure TKartKatmani.JogDurdur;
begin
  if FJogCalisiyor then FJogDuruyor := True;
end;

procedure TKartKatmani.JogDurusHizmeti;
var
  hepsiSifir: Boolean;
  i: Integer;
begin
  if Sifirlamada then
  begin
    JogSifirla;
    Exit;
  end;
  if not FJogDuruyor then Exit;
  if FKurulu then JogYurut(SIFIR);
  hepsiSifir := True;
  for i := 0 to EKSEN_SAYISI - 1 do
    if FJogAnlikHiz[i] <> 0 then hepsiSifir := False;
  if hepsiSifir or (not FKurulu) or (not FPort.Bagli) then JogSifirla;
end;

{ Her güncelleme döngüsünde çağrılan ana hizmet: kart durumunu, girişleri ve alarmları okur,
  bağlantıyı günceller ve adım sayaçlarını Mach3 DRO'larına kopyalar. }
procedure TKartKatmani.KonumuGuncelle;
var
  d: TKartDurumu;
  no: DWord;
  i, droKonum: Integer;
begin
  JogDurusHizmeti;
  FPort.Hizmet;
  KartBilgisiniDenetle;
  no := FPort.DurumAl(d);
  if no <> FKartDurumNo then
  begin
    FKartDurumNo := no;
    FKartDurumu := d;
    if FAnaProgram.GirisleriAktar(FKartDurumu.GirisBitleri) and (not Sifirlamada) then
      SifirlamayaGir(SIFIRLAMA_NEDENI_LIMIT);
  end;
  KartAlarminiDenetle;
  CikislariYenile;
  KurmayiDene;
  BaglantiyiDenetle;
  CikislariEsitle;
  BaglantiMesajlari;
  if FAnaProgram.KonumVar then
  begin
    for i := 0 to EKSEN_SAYISI - 1 do
    begin
      droKonum := FAnaProgram.KonumOku(i);
      if droKonum <> FSonYazilan[i] then
      begin
        FAdimlar[i] := FAdimlar[i] + (droKonum - FSonYazilan[i]);
        FIstenen[i] := FIstenen[i] + (droKonum - FSonYazilan[i]);
      end;
    end;
  end;
  DurusuUygula;
  for i := 0 to EKSEN_SAYISI - 1 do
  begin
    if FAnaProgram.KonumVar then FAnaProgram.KonumYaz(i, FAdimlar[i]);
    FSonYazilan[i] := FAdimlar[i];
  end;
  FGuncellemeBasina := 0;
end;

end.
