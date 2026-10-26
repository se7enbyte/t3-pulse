# T3 Pulse

macOS menü çubuğunda T3 Code ajanlarını ve işlerini gösterir.

- Mavi hareketli kesik halka: çalışıyor. Sarı: girdi/onay bekliyor.
- Yeşil tik: son 24 saatte tamamlanan işler. Kırmızı: hata.
- İkona tıklayınca tüm projelerin iş başlıkları, ajan modelleri, durumları ve süreleri açılır.
- İki saniyede bir yenilenir. Dock'ta görünmez. İsteğe bağlı tamamlanma sesi vardır.
- T3 Code kapalıysa son bilinen durum olarak işaretlenir.

## Derleme

macOS 14+ ve Xcode komut satırı araçları gerekir. Harici bağımlılık yoktur.

```sh
zsh build.sh
open 'build/T3 Pulse.app'
'build/T3 Pulse.app/Contents/MacOS/T3Pulse' --check
python3 tests/check_store.py
```

Varsayılan kaynak `~/.t3/userdata/statev2.sqlite` dosyasıdır. Farklı veri dizini için `T3CODE_HOME` ortam değişkeni kullanılabilir. SQLite bağlantısı salt okunurdur; sohbet metinleri ve kimlik bilgileri okunmaz. Ağ bağlantısı kullanılmaz.

Bu ilk sürüm T3 Code 0.1.2 yerel veritabanı şemasına bağlıdır. T3 güncellemesi şemayı değiştirirse uyarlama gerekebilir. “Tamamlandı” bir ajan turunun tamamlanmasıdır; projenin tüm hedeflerinin bitirildiği anlamına gelmez. T3 Code’dan çıkış sırasında süren işler, uygulama tekrar açılıp güncellenene kadar son bilinen durumda kalabilir.

Kaldırmak için menüdeki güç düğmesinden çıkıp `~/Applications/T3 Pulse.app` uygulamasını silin. Otomatik başlangıç kurulmaz.
