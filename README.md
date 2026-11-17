# Creativity Office — Yaratıcı Ofis

Windows PowerShell ile çalışan altı ajanlı fikir, eleştiri, küçük POC planı, maliyet,
karar ve puanlama hattı. Her görev kendi belgelerini, revizyonlarını ve sonuç raporunu tutar.
Altı rol aynı yapılandırılabilir Claude/Codex araç zincirini sırayla kullanır;
teslim paketi hazırlama yardımcı adımı da bu zincirle çalışır.

Bu depo kendi Git geçmişi, betikleri, istemleri ve testleriyle bağımsızdır.
Varsayılan yerel teslim modu başka bir depo gerektirmez. Kod uygulaması otomatik yapılmaz:
onaylı POC paketini bir uygulayıcıya verirsiniz, çıkan kanıtları geri ekleyerek puanlatırsınız.
İsteğe bağlı ana ofis köprüsü aynı paketi harici bir görev sistemine aktarabilir.

## Gereksinimler ve bağımlılıklar

- Windows 10/11 veya Windows Server, **Windows PowerShell 5.1**. Desteklenen/test edilen kabuk budur.
- Klonlama için Git. Ek PowerShell modülü, Python, Node.js veya paket kurulumu uygulamanın kendisi için gerekmez.
- Gerçek ajan çağrıları için en az bir **Claude Code** (`claude.exe`) veya **Codex CLI** (`codex.exe`),
  açık oturum, internet erişimi ve yapılandırdığınız modellere erişebilen hesap gerekir.
  CLI kurulum yönteminize göre kendi ek gereksinimleri olabilir.
- Kurulum ve oturum açma için resmi [Claude Code rehberi](https://code.claude.com/docs/en/quickstart)
  veya [Codex CLI rehberi](https://developers.openai.com/codex/cli/) izlenebilir.
- Sürüme/hesaba göre kullanılabilir model adları değişebilir; `roller.ortak` listesini hesabınıza göre ayarlayın.
  Şablon Claude `sonnet` ve Codex `gpt-6.1-sol` içerir; ikisini birden kurmak zorunlu değildir.
  İlk uygun araç başarısız olursa sıradaki denenir. Çağrılar hizmet kullanım hakkı tüketebilir.
- Çevrimdışı testler CLI, AI hesabı ve ağ gerektirmez. Makinece okunabilir özet: `bagimliliklar.json`.

## Kurulum

Windows PowerShell terminalinde:

```powershell
git clone https://github.com/oguzhanbalaban/creativity-office.git
cd creativity-office
Copy-Item .\ayarlar.json .\ayarlar.yerel.json
notepad .\ayarlar.yerel.json
```

`ayarlar.yerel.json` şablonun tamamının yerine geçer; alan bazında birleştirilmez.
`claude.exe` / `codex.exe` alanlarını gerekirse kurulu **yerel Windows yürütülebilir dosyasına** yönlendirin.
Boşsa Claude PATH üzerinden, Codex uygulama kurulumu/PATH üzerinden aranır.
Yalnızca kullandığınız sağlayıcıyı `roller.ortak` içinde bırakabilirsiniz.
Örneğin yalnız Codex için bu alanın değeri:

```json
"ortak": [{ "arac": "codex", "model": "gpt-6.1-sol", "efor": "high" }]
```

`ana_ofis_yolu` alanını boş bırakmak bağımsız yerel teslim modunu seçer.
`varsayilan_proje` için hedef proje adını ya da mutlak klasör yolunu yazın;
alternatif olarak her yeni görevde `-Proje` kullanın. Ajanlar hedefi değiştiremez.
`kadro.yerel.json` isteğe bağlıdır. Betikler yerel yapılandırma ve çalışma klasörlerini
Git dışında tutar; şablonları değiştirmez. Uygulama işletim sisteminin yürütme ilkesini değiştirmez.

## Kullanım

Tüm komutlar klonladığınız depo kökünden çalıştırılır.

```powershell
# Boş kuyruk kontrolü: hiçbir AI çağrısı yapmadan çıkar.
.\baslat.ps1 -Konsol -BosBitir

# Yeni konu ekle, kimliğini sakla ve hazır görevleri çalıştır.
$gorev = .\proje-ekle.ps1 -Konu "Metin tabanlı macera oyunu" -Alan "oyun" -Proje "C:\Projeler\Oyun"
.\durum.ps1
.\baslat.ps1 -Konsol -BosBitir
.\durum.ps1 -Id $gorev.id
```

Yerel teslimde onaylanan görev `bekleme` aşamasında durur; paketi
`gorevler/<id>/teslim.json` içinde bulursunuz. POC'u uygulayıp UTF-8 bir Markdown dosyasına
uygulama özetini, diff/commit bilgisini, test sonuçlarını ve eksik kalan kanıtları yazın.
Sonra bu dosyayı göreve ekleyip puanlayıcıyı çalıştırın:

```powershell
.\sonuc-ekle.ps1 -Id $gorev.id -Dosya "C:\Projeler\Oyun\uygulama-raporu.md"
.\baslat.ps1 -Konsol -BosBitir
.\durum.ps1 -Id $gorev.id
```

`sonuc-ekle.ps1` yalnızca yerel teslimi bekleyen görevlere boş olmayan çıktı kabul eder.
Kod yazmaz veya hedef projede komut çalıştırmaz. Nihai rapor `raporlar/<id>.md` ve
`gorevler/<id>/sonuc.md` altında oluşur.

```powershell
# Sürekli çalışma, tek adım, hata sonrası devam ve iptal:
.\baslat.ps1 -Konsol
.\baslat.ps1 -Konsol -AdimSiniri 1
.\durum.ps1 -Devam "gorev-kimligi"
.\durum.ps1 -Iptal "gorev-kimligi"
```

`-BosBitir` geleceğe ertelenmiş hata tekrarlarını/izlemeyi beklemez. Normal döngü kalp atışıyla
bekler. Durdurmak için depo kökünde `New-Item .\DURDUR -ItemType File` çalıştırın;
mevcut adımdan sonra çıkar. Yeniden çalıştırmadan önce `Remove-Item .\DURDUR` kullanın.
`Local\YaraticiOfisDongusu` mutex'i aynı Windows oturumunda tek döngüye izin verir;
farklı kurulumların aynı oturumda eşzamanlı döngü çalıştırması desteklenmez.

## İş akışı ve ayarlar

`yeni → fikir → elestiri → poc_plan → maliyet → karar → teslim → bekleme → puanlama → tamam`

Karar `ONAYLA`, `REVIZE` veya `REDDET` olmalıdır. Revizyonda eleştiri, plan, maliyet ve karar
yeniden çalışır. `revizyon_siniri` 0–3 aralığındadır; sınırdan sonra yeniden revizyon isteği reddedilir.
Geçersiz karar/puan başarılı sayılmaz. Puanlayıcı tek bir `PUAN: 1` … `PUAN: 10` satırı üretir.
Adım hataları artan beklemeyle `max_adim_denemesi` kez denenir; sonra görev `takildi` olur.
Sorunu düzelttikten sonra `durum.ps1 -Devam` kullanılır. İptal yerel takibi durdurur.

Önemli ayarlar: `gunluk_sinir` (sağlayıcı başına çağrı sınırı), `zaman_asimi_dk`,
`dongu.calisma_saatleri` (ör. `00:00-24:00` veya `22:00-06:00`), bekleme/izleme aralıkları.
Bildirimler varsayılan kapalıdır. Masaüstü ve isteğe bağlı ntfy ayarları `bildirim` içindedir.
Yerel ayarlara gizli anahtar yazmak yerine CLI'ın kendi oturum yönetimini kullanın.

İlk çalışmada `gorevler`, `durum`, `gunluk`, `raporlar`, `calisma` oluşur. Ajan istem ve yanıtları
görev altındaki `kayitlar/` içinde tutulur. Bunlar yerel çalışma verisidir ve Git'e eklenmez.
JSON/metin güncellemeleri `.bak` yedeğiyle atomik yazılır. Yerel ayarlar ve çalışma verilerini
taşımadan/temizlemeden önce ayrıca yedekleyin.

## İsteğe bağlı ana ofis köprüsü

`ana_ofis_yolu` açıkça yapılandırıldığında yerel teslim yerine `kopru.ps1` kullanılır.
Bu entegrasyon için harici kurulumun şu sözleşmeyi sağlaması gerekir:

- Kökte `gorev-ekle.ps1`; `-Proje`, `-Baslik`, `-Aciklama`, `-Kabul` parametrelerini kabul eder.
- Görevler `gorevler/<id>/gorev.md` ve `durum.json` altındadır; durum `id` ve `asama` içerir.
- Aşamalar: `yeni`, `plan`, `gelistirme`, `kontrol`, `denetim`, `kabul`, `tamamla`, `tamam`,
  `takildi`, `iptal`, `bekliyor_kullanici`.
- Tamamlanan görevin commit/dal bilgileri ile görev altındaki diff, kontrol ve denetim
  raporları okunur. Eksik ya da kesilen kanıtlar puanlayıcıya bildirilir.

Göreli köprü yolu bu depo kökünden çözülür; ortak betik importu ya da ortak Git geçmişi yoktur.
Teslim anahtarı yinelenen görevleri engeller. Önceki çağrının sonucu belirsizse otomatik tekrar
gönderilmez. Harici görevlerde `[yaratici-ofis:<anahtar>]` işaretini kontrol edin. Görev bulunduysa
`-Devam` uzlaştırır. Hiç oluşmadığını doğruladıysanız yerel `teslim-kaydi.json` ve `.bak` dosyasını
yedekleyip kaldırarak yeniden deneyebilirsiniz. Teslimden sonra köprü yolu görevde sabitlenir.
Harici sistemde `takildi`/`iptal` yerel görevi de durdurur; iptal komutu harici görevi iptal etmez.

## Web paneli

Depo kökünde tek komutla başlatın (Node.js, npm, ek modül veya yönetici izni gerekmez):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ofis\ofis.ps1 -Ac
```

Tarayıcıda **http://127.0.0.1:8766/** açılır. Konsolda günlük görmek için `-Konsol`
ekleyin. Bu terminali açık bırakın. Aynı Windows oturumunda ikinci panel sunucusu
başlamaz; `-Ac` mevcut paneli açar. Özel port için `-Port 8770` kullanabilirsiniz;
port doluysa sunucu açık hata verir, sessizce başka porta geçmez. AI Ekip panelinin
8765 portuyla çakışmaz.

Panel altı ajanın durumunu, görevleri, revizyon ve puanları, fikirden puanlamaya
iş hattını ve görev belgelerini dört saniyede bir günceller. **Yeni konu** formu
`proje-ekle.ps1` üzerinden kuyruğa görev ekler. Takılan görev devam ettirilebilir;
açık görev iptal edilebilir. Döngü durduğunda görev verileri görünmeye devam eder.
Panel, ajan döngüsünü kendiliğinden başlatmaz: görevleri işlemek için ayrı terminalde
`.\baslat.ps1 -Konsol` çalıştırın. Teslim sonrası kanıt eklemek için yukarıdaki
`sonuc-ekle.ps1` komutu kullanılır. Altı kadrolu role ek olarak teslim hazırlığı
yardımcı bir adımdır.

Paneli durdurmak için **Paneli durdur** düğmesine, sunucu terminalinde **Ctrl+C**'ye
basın veya ikinci terminalde tek komut çalıştırın:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\ofis\ofis.ps1 -Durdur
```

Sekmeyi kapatmak sunucuyu hemen durdurmaz; varsayılan olarak 60 dakika istek
gelmezse kapanır (`-BosKapanDk 10`; `0` otomatik kapanmayı kapatır). Bu işlemler
yalnızca paneli durdurur; ajan döngüsünü durdurmak için **Kullanım** bölümündeki
`DURDUR` dosyası yöntemini kullanın.

Sunucu yalnızca `127.0.0.1` üzerinde dinler. Host, Origin ve Sec-Fetch-Site denetimleri
ve bütün API isteklerinde `X-Oturum` doğrulaması vardır. Oturum anahtarı her açılışta
yenilenir ve diske yazılmaz. `/api/durum` görevleri, kalp atışını, sayaçları ve kadroyu;
`/api/gorev?id=...` görev belgelerini döndürür. API'ler panel oturumu gerektirir.
`ofis/sunucu.json` yalnızca PID/port/başlangıç bilgisi, `ofis/ofis.log` sunucu günlüğüdür;
ikisi de Git dışındadır. Veri dosyaları döngünün atomik yazmalarını engellemeden okunur.
Panel koyu/açık sistem temasını, küçük ekranları ve azaltılmış hareket tercihini destekler.

## Test ve doğrulama

```powershell
powershell.exe -NoProfile -NonInteractive -File .\testler\akis.test.ps1
powershell.exe -NoProfile -NonInteractive -File .\testler\panel.test.ps1
```

Testler depo içindeki geçici kopyada sahte ajanlar ve isteğe bağlı köprünün küçük sözleşme
düzeneğini kullanır; üst klasörden dosya almaz. Sözdizimi/UTF-8 BOM, boş kuyruk, yedek araç,
çağrı sınırı, revizyon/red, teslim tekilliği, hata kurtarma, yerel çıktı ve puanlama doğrulanır.
Gerçek AI/ağ çağrısı, kurulum, commit, zamanlanmış görev veya sistem ayarı değişikliği yapılmaz.
Canlı model yanıtları ve harici görev sisteminin tamamı bu çevrimdışı testin kapsamı dışındadır.

## Lisans

MIT — [LICENSE](LICENSE). İlk kaynak kodun telif bildirimi korunmuştur;
bağımsız sürüm Creativity Office contributors katkılarını da içerir.
