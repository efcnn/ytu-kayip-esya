# 🎓 YTÜ Kayıp Eşya Platformu

Yıldız Teknik Üniversitesi (YTÜ) kampüsleri içerisinde öğrencilerin kaybettikleri veya buldukları eşyaları kolayca paylaşabilmesi için geliştirilmiş, gerçek zamanlı ve modern bir web uygulamasıdır. 

Bu proje, karmaşık üyelik sistemleri yerine kullanıcı deneyimini (UX) ön planda tutan pratik mimarisi ve kendi kendini temizleyen veritabanı yapısıyla öne çıkmaktadır.

---

## 📸 Ekran Görüntüleri

### Masaüstü ve Mobil Uyumluluk (Responsive Design)
Platform, hem bilgisayarlarda hem de telefonlarda kusursuz bir deneyim sunar.

| Masaüstü Görünüm | Mobil Görünüm |
| :---: | :---: |
| ![Masaüstü Ana Ekran](./screenshots/Ekran%20görüntüsü%202026-10-17%20182847.png) | ![Mobil Ana Ekran](./screenshots/Ekran%20görüntüsü%202026-10-17%20182946.png) |

### Form ve İlan Detay Ekranları
Kullanıcılar hızlıca form doldurabilir ve ilan detaylarını pop-up (dialog) ekranlarında görüntüleyebilir.

| Kayıp/Bulundu Formları | İlan Detay Görünümü |
| :---: | :---: |
| ![Kayıp Formu](./screenshots/Ekran%20görüntüsü%202026-10-17%20182859.png) ![Bulundu Formu](./screenshots/Ekran%20görüntüsü%202026-10-17%20182906.png) | ![Detay Ekranı](./screenshots/Ekran%20görüntüsü%202026-10-17%20182935.png) |

*(Görsel: Sadece filtreye uyan spesifik ilanların listelenmesi)*
![Filtrelenmiş İlan](./screenshots/Ekran%20görüntüsü%202026-10-17%20182919.png)

---

## 🚀 Öne Çıkan Teknik Özellikler (Under the Hood)

Bu proje sadece basit bir CRUD (Oluştur, Oku, Güncelle, Sil) uygulaması değil, aynı zamanda veritabanı optimizasyonu ve anonim kullanıcı yönetimi konularında akılcı çözümler barındırır.

### 1. Gerçek Zamanlı Veri Akışı (Real-time Stream)
Uygulama, **Firebase Cloud Firestore** ile entegredir. Ana sayfa, verileri statik olarak bir kez çekmek yerine `StreamBuilder` kullanarak dinler. Bu sayede, kampüsteki başka bir öğrenci yeni bir ilan eklediğinde, sayfanızı yenilemenize bile gerek kalmadan ilan anında ekranınıza düşer.

### 2. Akıllı Yetkilendirme (Zorunlu Üyelik Olmadan Silme Hakkı)
Kullanıcıların sadece bir eşya ilanı vermek için uzun uzun üye olma veya giriş yapma adımlarıyla uğraşmasını engellemek istedik. Ancak güvenliği de sağlamalıydık: **"Herkes sadece kendi ilanını silebilmeli."**
* **Çözüm:** Kullanıcı bir ilan oluşturduğunda, o ilanın Firestore'daki benzersiz `Document ID`'si, kullanıcının cihaz hafızasına (`shared_preferences` paketi ile) gizlice kaydedilir. Kullanıcı bir ilan detayına tıkladığında, sistem ilanın ID'sini cihazdaki listeyle karşılaştırır. Eşleşme olursa, ekranda sadece o kullanıcıya özel "Sil (Çöp Kutusu)" butonu belirir. 

### 3. Otomatik Veritabanı Temizliği (Firestore TTL)
Üniversite gibi aktif ortamlarda "bulunan" bir eşyanın ilanı aylar sonra hala sistemde durursa veritabanı çok hızlı bir şekilde "ilan çöplüğüne" döner.
* **Çözüm:** Firebase'in **Time-To-Live (TTL)** özelliği projeye entegre edildi. Her ilan oluşturulduğunda kod blokları otomatik olarak o ana 15 gün ekler ve `expiresAt` (son kullanma tarihi) adında bir veri damgası oluşturur. Firestore sunucuları bu tarihi takip eder ve 15 günü dolan ilanları arka planda otomatik olarak siler. Sunucu maliyeti sıfıra iner, liste her zaman güncel kalır.

## 🚧 Geliştirme Notları: Fotoğraf Yükleme Mimarisi
Proje şu an aktif geliştirme aşamasındadır. Bulut depolama (Firebase Storage) maliyetlerini optimize etmek ve ilk aşamada temel veritabanı akışına (Core CRUD) odaklanmak amacıyla, forma yüklenen fotoğraflar geçici olarak sunucuda tutulmamaktadır. 
Tasarım bütünlüğünü korumak ve testleri gerçekleştirmek için ilanlara rastgele (placeholder - *picsum.photos*) görseller atanmaktadır. İlerleyen güncellemelerde tam kapsamlı Storage entegrasyonu sağlanacaktır.

## 🛠️ Kullanılan Teknolojiler

* **Frontend:** Flutter (Web), Dart
* **Backend:** Firebase Core, Cloud Firestore
* **Local Storage:** Shared Preferences
* **Mimari Yapı:** Stream-based State Management, Custom LayoutBuilder (Responsive)

---

## ⚙️ Kurulum ve Çalıştırma

Projeyi kendi bilgisayarınızda çalıştırmak için aşağıdaki adımları izleyebilirsiniz:

1. Depoyu klonlayın:
   ```bash
   git clone https://github.com/KULLANICI_ADIN/ytu-kayip-esya.git
   ```
2. Gerekli paketleri indirin:
   ```bash
   flutter pub get
   ```
3. Projeyi web tarayıcısında başlatın:
   ```bash
   flutter run -d chrome
   ```
   *(Not: Firebase bağlantısının kendi projenizde çalışması için Firebase CLI ile kendi `firebase_options.dart` dosyanızı oluşturmanız gerekmektedir.)*