# T3 Pulse

macOS menü çubuğunda T3 Code ajanlarını ve işlerini gösterir.

- Mavi hareketli kesik halka: çalışıyor. Sarı: girdi/onay bekliyor.
- Yeşil tik: son 24 saatte tamamlanan işler. Kırmızı: hata.
- İkona tıklayınca tüm projelerin iş başlıkları, ajan modelleri, durumları ve süreleri açılır.
- İki saniyede bir yenilenir. Dock'ta görünmez. İsteğe bağlı tamamlanma sesi vardır.
- T3 Code kapalıysa son bilinen durum olarak işaretlenir.
- Aynı sohbette daha yeni bir istek iptal edilse bile devam eden iş öncelikli gösterilir.

## Kurulum

**Gerekenler:** macOS 14 veya üzeri ve kurulu bir T3 Code. Önce T3 Code’u en az bir kez açın. Apple Silicon ve Intel Mac’lerde kullanılabilir.

**1. Geliştirici araçlarını hazırlayın.** Terminal’i açın. Xcode komut satırı araçları yüklü değilse şu komutu çalıştırıp açılan kurulumun bitmesini bekleyin:

```sh
xcode-select --install
```

Araçlar zaten yüklüyse bu adımı atlayabilirsiniz. Tam Xcode uygulamasını kurmanız gerekmez.

**2. Uygulamayı indirip derleyin.** Terminal’de aşağıdaki komutları sırasıyla çalıştırın:

```sh
git clone https://github.com/se7enbyte/t3-pulse.git
cd t3-pulse
zsh build.sh
```

**3. Kurup açın.** Aşağıdaki komutlar uygulamayı kullanıcı hesabınızdaki Applications klasörüne kopyalar ve başlatır:

```sh
mkdir -p "$HOME/Applications"
ditto 'build/T3 Pulse.app' "$HOME/Applications/T3 Pulse.app"
open "$HOME/Applications/T3 Pulse.app"
```

Menü çubuğunda durum ikonları görünür. İkona tıklayarak işleri ve ajanları görebilirsiniz. Dock’ta simge görünmemesi normaldir. Daha sonra aynı uygulamayı Finder’dan açabilirsiniz; Mac açıldığında otomatik başlamaz. Yeni bir kopya açmadan önce çalışan T3 Pulse’tan menüdeki güç düğmesiyle çıkın.

## İsteğe bağlı kontroller

Proje klasöründe canlı durumları bir kez okumak veya testleri çalıştırmak için:

```sh
'build/T3 Pulse.app/Contents/MacOS/T3Pulse' --check
python3 tests/check_store.py
```

Testler için Python 3 gerekir; uygulamanın çalışması için gerekmez. `--check` iş başlıklarını Terminal’e yazar.

Varsayılan kaynak `~/.t3/userdata/statev2.sqlite` dosyasıdır. Farklı veri dizini için `T3CODE_HOME` ortam değişkeni kullanılabilir. SQLite bağlantısı salt okunurdur; sohbet metinleri ve kimlik bilgileri okunmaz. Ağ bağlantısı kullanılmaz.

Bu ilk sürüm T3 Code 0.1.2 yerel veritabanı şemasına bağlıdır. T3 güncellemesi şemayı değiştirirse uyarlama gerekebilir. “Tamamlandı” bir ajan turunun tamamlanmasıdır; projenin tüm hedeflerinin bitirildiği anlamına gelmez. T3 Code’dan çıkış sırasında süren işler, uygulama tekrar açılıp güncellenene kadar son bilinen durumda kalabilir.

Kaldırmak için menüdeki güç düğmesinden çıkıp `~/Applications/T3 Pulse.app` uygulamasını silin. Otomatik başlangıç kurulmaz.
