# SafCNC Mach3 Eklentisi

Bir CNC makinesini USB üzerinden **Arduino Uno / Nano** ile süren Mach3 hareket eklentisi.
Protokol Arduino'ya bağlı değildir: STM32 kart yaklaşık 100 kHz'e çıkabilir (test edilmedi, aşağıya bakın).
Yörüngeyi Mach3 planlamaya devam eder; eklenti onu 5 ms'lik dilimler halinde karta aktarır,
kart da adım ve yön sinyallerini 32 kHz zamanlayıcıyla üretir.

**Free Pascal (Lazarus)** ile düz bir Win32 DLL olarak yazılmıştır - LCL ya da dış kitaplık kullanılmaz.

| | |
|---|---|
| Kart yazılımı | [SafCNC_Arduino](https://github.com/fikretpalas/SafCNC_Arduino) |
| Bu eklentinin İngilizce sürümü | [SafCNC_Mach3Plugin_en](https://github.com/fikretpalas/SafCNC_Mach3Plugin_en) |

Bu depoda dosya adları, tanımlayıcılar, açıklamalar ve kullanıcıya gösterilen metinler Türkçedir.
Tanımlayıcılar yalnızca ASCII harflerle yazılmıştır. Win32 API ve Mach3 SDK adları
(`Engine`, `MainPlanner`, `DoButton`, `CreateFileA` ...) özgün hâlleriyle bırakılmıştır.

## Nasıl çalışır

```
 Mach3 (32 bit)                         SafCNC.dll                                Arduino Uno / Nano
+------------------+   yörünge      +---------------------------------+   USB    +------------------------+
| G-kod            |   noktaları    | uCihaz        Mach3 olayları,jog|   seri   | halka tampon 200 dilim |
| yörünge          | -------------> | uKartKatmani  dilimler, konum   |  115200  | 32 kHz DDA zamanlayıcı |
| planlayıcı, DRO  | <------------- | uSeriBaglanti iş parçacıkları   | <------> | limit, prob, acil stop |
+------------------+   konum,       +---------------------------------+  paketler+------------------------+
                       girişler                                                    adım / yön / etkin
```

* Mach3 hareketi planlar ve yörünge tamponunu doldurur.
* `uCihaz` noktaları alır, `uKartKatmani` her 5 ms'lik dilimi eksen başına tam adıma çevirir
  (kesirler sonraki dilime taşınır, adım kaybolmaz), `uSeriBaglanti` bunları paket olarak kuyruğa koyar.
* Bir okuma ve bir yazma iş parçacığı kartla çakışmalı (overlapped) G/Ç üzerinden konuşur; Mach3 USB'yi hiç beklemez.
* Kart her 50 ms'de bir durum paketi gönderir: durum, tampon doluluğu, çıkışlar ve girişler.
* Her duruştan sonra kart hareketin bittiği dilimi ve alt vuruşu bildirir; eklenti Mach3 konumunu
  gerçekten atılmış adımlara göre düzeltir.

## Özellikler

* 3 eksen (X, Y, Z); kart kendi hız sınırını bildirir: Arduino'da 5 ms'lik dilimde 160 adım = eksen
  başına 32 kHz, en fazla 500 adım = 100 kHz
* Kartı herhangi bir COM portunda kendiliğinden bulur (önce USB seri portlar); tak-çıkar ve yeniden bağlanma
* İvmeli jog; tuş bırakılınca makine çabuk dursun diye kart tamponu kısa tutulur
* G4 bekleme, fener mili açma / yön, soğutma ve sis çıkışları
* Limit, prob, Feed Hold, Cycle Start ve acil stop girişleri Mach3 giriş sinyallerine aktarılır
* *PlugIn Control > SafCNC* altında bağlantı lambası, port ve baud hızını gösteren durum penceresi
* Her bağlantı ve hata olayı için Mach3 durum satırında mesaj
* Kayıt defterine hiçbir şey yazılmaz; eklentinin kendine ait ayarı yoktur

## Güvenlik tasarımı

* Her pakette sıra sayacı ve 16 bit sağlama toplamı vardır.
* Bağlantı 200 ms sessiz kalırsa kart kendiliğinden durur; eklenti de aynı zaman aşımını uygular.
* Limit anahtarları, prob ve kartın kendi acil stop girişi PC'den bağımsız olarak kartta işlenir.
* Her kart ya da bağlantı hatası Mach3'ü sıfırlamaya alır ve nedeni gösterilir.
* *Motor Tuning* hızları kartın bildirdiği hızı aşıyorsa her ekseni ve izin verilen en yüksek hızı
  gösteren bir uyarı açılır; hızlar düşürülene kadar kart bağlanmaz. Eklenti Mach3 ayarlarını kendisi
  değiştirmez.
* Mach3 klavye odağını kaybedince, ters yön tuşlarına basılınca ya da 30 ms boyunca hiçbir tuş ve
  fare düğmesi basılı değilse jog durur.
* Jog sırasında Mach3'ün başlık çubuğuna, çerçevesine ya da menü çubuğuna tıklanınca Windows Mach3
  penceresini bekletir, sürüklenirse pencere kayar. Jog tuşu basılıyken ya da jog sürerken böyle bir
  tıklama Windows'a iletilmez: pencere kaymaz, makine yumuşakça yavaşlayıp durur ve tüm jog tuşları
  bırakılana kadar jog kilitli kalır.
* Pencere başlık çubuğundan sürüklenirken bir tuşa basılırsa pencere eski yerine konur, taşıma iptal
  edilir ve tüm tuşlar bırakılana kadar jog kilitli kalır.
* Mach3 hiçbir jog çalışmazken "jog yapıyor" durumunda kalırsa (örneğin bir metin kutusunun içinde jog
  tuşuna basıldıktan sonra), eklenti makine durunca bu durumu temizler; sıfırlama gerekmez.
* Eklenti açılışta Mach3 bellek düzenini denetler; uymazsa kendini devre dışı bırakır.

> CNC makineleri insanlara zarar verebilir ve takımları kırabilir. Her zaman motor ve fener mili gücünü
> kesen donanımsal bir acil stop kullanın. Bu yazılım hiçbir garanti verilmeden sunulmaktadır.

## Kaynak dosyalar

| Dosya | Görevi |
|---|---|
| `SafCNC.lpr` | Kitaplık giriş noktası, Mach3'e dışa aktarılan işlevler, menü kancası |
| `uCihaz.pas` | Üst düzey denetleyici: hareket, jog, bekleme, prob ve sıfırlama olayları |
| `uKartKatmani.pas` | Dilimler, konum sayma, çıkışlar, alarmlar, bağlantı durumu |
| `uSeriBaglanti.pas` | COM port arama, okuma / yazma iş parçacıkları, paket denetimi, bekçi |
| `uKartProtokol.pas` | Kart yazılımıyla ortak paket biçimi |
| `uAnaProgram.pas` | Mach3 Engine / MainPlanner bloklarına ve geri çağırma işlevlerine erişim |
| `uKartPenceresi.pas` | Win32 API ile çizilen durum penceresi |
| `uMesajlar.pas` | Kullanıcıya gösterilen tüm metinler |
| `uSistemApi.pas` | Win32 API tanımları |

## Derleme

Mach3 32 bit bir programdır; DLL **mutlaka** `i386-win32` hedefiyle derlenmelidir.

1. [Lazarus](https://www.lazarus-ide.org/) ve Free Pascal 3.2.x kurun. 64 bit Lazarus kullanıyorsanız
   `i386-win32` çapraz derleyicisini ekleyin ya da doğrudan 32 bit Lazarus kurulumunu kullanın.
2. `SafCNC.lpi` dosyasını açın. Proje CPU `i386`, işletim sistemi `win32`, çıktı türü *Library* olarak ayarlıdır.
3. *Çalıştır > Derle* ile `SafCNC.dll` oluşur.

64 bit derleme, kaynak koddaki `{$FATAL}` denetimiyle derleme anında reddedilir.

## Kurulum

1. [SafCNC_Arduino](https://github.com/fikretpalas/SafCNC_Arduino) deposundaki yazılımı karta yükleyin.
2. `SafCNC.dll` dosyasını `Mach3\PlugIns` klasörüne kopyalayın.
3. Mach3'ü başlatın. Hangi hareket denetim aygıtının kullanılacağı sorulursa SafCNC'yi seçin.
4. Mach3 *Reset* düğmesiyle sıfırlamadan çıkın; durum satırında `SafCNC kartı bağlandı.` yazar.

## Mach3 Ports & Pins

Kart Mach3'e **port 3** olarak görünür.

| Giriş pini | Karttaki sinyal | | Çıkış pini | Karttaki sinyal |
|---|---|---|---|---|
| 1 | X limit (D9) | | 1 | Fener mili açık (D11) |
| 2 | Y limit (D10) | | 2 | Fener mili yönü (D13) |
| 3 | Z limit (D12) | | 3 | Soğutma sıvısı (A3) |
| 4 | Feed Hold (A1) | | 4 | Sis soğutma (A4) |
| 5 | Cycle Start (A2) | | | |
| 6 | Acil stop (A0) | | | |
| 7 | Prob (A5) | | | |

Adım ve yön pinleri kartta sabittir (GRBL 1.1 / CNC Shield V3 düzeni); Mach3'te pin ataması gerekmez.
Birim başına adım, hız ve ivme değerleri *Motor Tuning* ekranından alınır. Kart bağlı değilken
Mach3'e protokolün tavanı (100 kHz) bildirilir, hızlar buna kadar ayarlanabilir; kart bağlanınca kartın
kendi sınırı geçerli olur.

## Kısaca protokol

| Yön | Paket | Boy | İçerik |
|---|---|---|---|
| PC -> kart | durum (`K_SIFIRLA`, `K_HAZIR`, `K_KURULU`) | 8 bayt | komut, sayaç, sıfırlama nedeni ya da fener mili + çıkışlar, sağlama |
| PC -> kart | hareket (`K_HAREKET`) | 10 bayt | komut, sayaç, sonraki 5 ms için X / Y / Z adımları, sağlama |
| kart -> PC | durum | 8 bayt | durum, sayaç, tampon doluluğu, fener mili, çıkışlar, girişler, sağlama |
| kart -> PC | bilgi (`K_BILGI`), açılışta ve yeni bağlantıda | 8 bayt | komut, sayaç, dilim başına adım sınırı (16 bit), dilim başına alt vuruş (16 bit), sağlama |

Sağlama toplamı, tüm baytların 16 bit toplamını sıfır yapar. Kart adım sınırını `K_BILGI` ile bildirir;
diğer sabitler `uKartProtokol.pas` içindedir ve kart yazılımıyla aynı olmalıdır.

## Diğer kartlar (STM32)

Eklenti yalnızca Arduino için değildir. Aynı paket protokolünü uygulayan her kartla konuşur ve
tasarım daha hızlı donanıma da açıktır: STM32 kart eksen başına yaklaşık **100 kHz** hıza
(5 ms'lik dilimde 500 adım) çıkabilir.

* Arduino Uno / Nano yaklaşık 30 kHz üzerine çıkamaz; yüksek hız STM32 donanımı içindir.
* STM32 tarafı henüz **test edilmedi**.
* Kart çalışma hızını `K_BILGI` paketiyle bildirir; eklenti dilimleri o hıza göre planlar ve dilim
  başına 500 adımı hiçbir zaman geçmez.

## Şimdiki sınırlar

* Üç eksen; A ekseni sürülmez.
* Fener mili çıkışı yön bilgisiyle birlikte aç / kapa biçimindedir; devir Mach3'ten ayarlanmaz.
* Prob hareketi (G31) ve referansa gitme bu sürümde kart tarafından yürütülmez.

## Geliştirici

**Fikret Palas** - <safcnc@tutamail.com> - <https://github.com/fikretpalas>

## Lisans

[MIT](LICENSE)
