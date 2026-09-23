# TilikSuara

**Pendataan pemilih dari lapangan, tetap berjalan tanpa internet.**

TilikSuara membantu petugas mencatat data warga untuk Daftar Pemilih Sementara (DPS), memeriksa isian, dan menyiapkan rekap Excel. Dirancang untuk satu petugas di satu perangkat Android, dengan data yang tersimpan di ponsel.

**Android 7.0+ · Tanpa akun · Sepenuhnya offline · Lisensi MIT**

[Mulai Menggunakan](#mulai-menggunakan) · [Fitur](#fitur) · [Ekspor](#ekspor-dan-tanda-bukti) · [Privasi](#privasi-dan-penyimpanan) · [Pengembangan](#pengembangan)

## Fitur

| Kebutuhan | Yang tersedia |
| --- | --- |
| Mengatur wilayah kerja | Pilihan provinsi hingga desa dari data wilayah bawaan, isian manual, serta beberapa RT / RW dalam satu wilayah kerja. |
| Mencatat warga | Formulir identitas, keterangan, persentase kelengkapan, draf warga baru, dan **Simpan & Lanjut** untuk pendataan berurutan. |
| Menata daftar | Sisip sebelum atau sesudah warga, ubah urutan, penanda warna, pencarian, dan filter keterangan. |
| Mencari data | Pencarian nama dengan toleransi variasi ejaan atau pencarian tanggal lahir, dengan prioritas RT aktif. |
| Memakai data lama | Impor `.xlsx` atau `.csv`, pilih lembar dan petakan kolom, lalu gunakan referensi untuk membantu pengisian. Referensi yang memenuhi persyaratan isian dapat dijadikan data warga satu per satu atau sekaligus. |
| Memeriksa isian | Pengingat format NIK, kesesuaian tanggal lahir dan jenis kelamin, daftar duplikat NIK atau nama, serta catatan tanpa NIK. |
| Menyiapkan hasil | Excel per RT atau gabungan, lembar temuan, kop opsional, dan tanda bukti untuk warga terpilih. |
| Menelusuri perubahan | Riwayat terbaru, jurnal perubahan, salinan data otomatis, perbandingan isi, dan pemulihan cadangan. |

TilikSuara membantu pencatatan, bukan menentukan hak pilih. Data tetap perlu dicocokkan dengan dokumen kependudukan. Aplikasi tidak menghitung kelayakan berdasarkan usia dan tidak mengambil foto dokumen.

## Mulai Menggunakan

1. **Pasang APK dan tentukan lokasi kerja.** Pilih wilayah dari daftar atau isi secara manual. Aplikasi tidak meminta izin penyimpanan saat pertama dibuka.
2. **Tambahkan RT / RW di Beranda.** Pilih RT yang sedang dikerjakan. Ringkasan jumlah warga dan isian tanpa NIK tersedia pada kartu wilayah kerja.
3. **Impor referensi jika diperlukan.** Buka **Referensi → Impor Berkas**, pilih Excel atau CSV, lalu periksa pemetaan kolom. Untuk berkas dengan beberapa lembar, impor lembar data RT satu per satu.
4. **Mulai dari Daftar Warga.** Tekan **Tambah**, cari warga yang sudah tercatat atau referensi yang sesuai, lalu lengkapi formulir. NIK boleh dikosongkan jika belum tersedia. Pengingat NIK tidak menghalangi penyimpanan, sedangkan NIK ganda meminta konfirmasi.
5. **Periksa dan ekspor.** Buka **Ekspor & Pemulihan** untuk memeriksa duplikat dan membuat Excel. Urutan hasil ekspor mengikuti susunan warga yang disimpan.
6. **Buat cadangan sebelum selesai.** Gunakan **Buat Snapshot Sekarang**, izinkan akses berkas agar salinan ZIP tersimpan di luar aplikasi, lalu salin cadangan secara berkala ke tempat yang aman.

Pada formulir, keterangan dapat berupa catatan bebas atau pilihan cepat: **TMS** (Tidak Memenuhi Syarat), **PD** (Pindah Domisili), **B** (Baru), dan **MD** (Meninggal Dunia).

## Ekspor dan Tanda Bukti

### Rekap DPS

Menu **Ekspor & Pemulihan** menyediakan pilihan RT aktif atau semua RT pada RW aktif, satu berkas per RT atau satu berkas gabungan, serta kop di atas tabel.

| Isi berkas Excel | Keterangan |
| --- | --- |
| Lembar RT | Nomor, nama, NIK, jenis kelamin, tempat dan tanggal lahir, desa, RT, RW, serta keterangan. Nomor dimulai dari 1 pada setiap RT. |
| Lembar temuan | `DUPLIKAT NIK`, `DUPLIKAT NAMA`, dan `TANPA NIK` muncul jika ada data yang perlu diperiksa. |
| `INFO` | Identitas wilayah, jumlah warga, waktu ekspor, dan informasi aplikasi. |

Setiap ekspor manual masuk ke folder baru di `ekspor/`. Berkas dapat dibuka dengan aplikasi spreadsheet atau dibagikan setelah konfirmasi. Membuat berkas tidak otomatis mengirimkannya.

### Tanda Bukti

Dari menu **Daftar Warga → Tanda Bukti**, pilih warga dan lengkapi informasi cetak untuk menghasilkan berkas Excel. Status perkawinan, pilihan dokumen, serta nama kepala rumah tangga, petugas, dan penerima hanya dipakai untuk tanda bukti tersebut. Isian ini tidak menambah atau mengubah data utama warga.

## Privasi dan Penyimpanan

APK release tidak memiliki izin internet. Data utama, jurnal, salinan data, dan arsip impor disimpan di ruang privat aplikasi. Pencadangan otomatis Android dinonaktifkan dalam konfigurasi aplikasi.

| Lokasi | Isi dan penggunaan |
| --- | --- |
| Ruang privat aplikasi | Data warga dan referensi, jurnal perubahan, snapshot, serta arsip impor dan pemulihan. Pendataan tidak memerlukan izin penyimpanan publik. |
| `Documents/Pantarlih<Desa>_<kode>/ekspor/` | Excel DPS dan tanda bukti. Salinan Excel otomatis berada di `otomatis/`. |
| `Documents/Pantarlih<Desa>_<kode>/cadangan/` | Cadangan ZIP berisi salinan basis data dan jurnal perubahan. |
| `Documents/Pantarlih<Desa>_<kode>/impor/` | Tempat menaruh berkas referensi agar mudah ditemukan. |

Nama folder menyesuaikan desa dan kode wilayah yang tersedia. Nama `Pantarlih` tetap digunakan agar kompatibel dengan berkas dari versi sebelumnya.

Izin akses berkas baru diminta saat menggunakan ekspor, impor, atau pencadangan ke folder publik. Android 11 ke atas menggunakan izin **Kelola Semua File**, sementara Android 7–10 menggunakan izin penyimpanan. Berpindah RT tidak membuka permintaan izin.

**Data dan cadangan tidak dienkripsi oleh aplikasi.** Gunakan kunci layar, simpan salinan cadangan di tempat aman, dan pilih penerima berkas dengan cermat. Aplikasi lain yang dipilih untuk membuka atau membagikan Excel dapat memiliki akses internet sendiri.

**Menghapus aplikasi atau menghapus data aplikasi akan menghilangkan data privat.** Cadangan yang sudah tersimpan di folder publik terpisah dari data tersebut. Pastikan ZIP cadangan tersedia dan telah disalin sebelum mengganti perangkat atau menghapus aplikasi. Excel adalah rekap, bukan pengganti cadangan pemulihan.

## Cadangan dan Pemulihan

Perubahan data dicatat ke jurnal sebelum diterapkan ke basis data. Saat aplikasi dibuka, catatan yang belum diterapkan dapat diputar ulang. Jurnal juga dipakai untuk membangun ulang data saat diperlukan.

- Saat berpindah RT aktif, aplikasi membuat **snapshot** atau salinan data di ruang privat. Setelah izin berkas tersedia, aplikasi juga membuat cadangan ZIP dan ekspor Excel otomatis.
- Aplikasi menyimpan **20 snapshot terbaru**, **10 cadangan ZIP terbaru**, dan **10 hasil ekspor otomatis terbaru**. Ekspor manual tidak mengikuti rotasi ini.
- **Snapshot** menyediakan pratinjau, perbandingan dengan data aktif, dan pemulihan ke salinan yang dipilih.
- **Jurnal** menyediakan penelusuran perubahan, pemeriksaan catatan, pengembalian versi, dan pembatalan penghapusan warga.
- **Pulihkan dari Cadangan** memuat ZIP yang sebelumnya dibuat aplikasi. Data aktif diganti dengan isi cadangan, sehingga perubahan setelah cadangan dibuat tidak muncul pada hasil pemulihan. Data sebelumnya diamankan di ruang privat untuk keperluan pemulihan lanjutan.

Cadangan pada ponsel yang sama belum melindungi dari kehilangan atau kerusakan perangkat. Salin ZIP terbaru secara berkala, misalnya ke komputer melalui USB.

## Pengembangan

Proyek menggunakan Flutter, SQLite melalui `sqflite`, dan paket `excel`. Versi aplikasi serta batas SDK tersedia di [`pubspec.yaml`](pubspec.yaml), dependensi terkunci di [`pubspec.lock`](pubspec.lock), dan konfigurasi Android berada di [`android/app/build.gradle.kts`](android/app/build.gradle.kts).

Siapkan Flutter yang kompatibel dengan dependensi terkunci, Android SDK yang sesuai konfigurasi proyek, dan **JDK 17**.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter build apk --release --split-per-abi
```

Jalankan tes secara berurutan karena pengujian SQLite memakai `sqflite_common_ffi`. Tes meliputi aturan data, urutan warga, jurnal dan pemulihan, impor-ekspor, serta perilaku layar. Beberapa tes impor dengan berkas pribadi hanya berjalan jika berkas tersedia lokal. Berkas tersebut tidak dibundel ke APK.

APK hasil build berada di `build/app/outputs/flutter-apk/`. Pilih varian ABI yang sesuai perangkat. Untuk mengembangkan pada perangkat yang sudah berisi data, buat cadangan terlebih dahulu dan pertahankan identitas paket serta kunci penandatanganan saat memperbarui.

> **Penandatanganan APK:** konfigurasi release saat ini menggunakan kunci debug Android untuk pemasangan langsung. Kunci tersebut bergantung pada lingkungan build, sehingga build dari komputer lain belum tentu dapat memperbarui instalasi yang sama. Distribusi jangka panjang memerlukan kunci penandatanganan tetap yang disimpan dengan aman. Mengganti kunci tidak otomatis kompatibel dengan instalasi lama, dan menghapus aplikasi untuk mengatasi masalah tanda tangan akan menghapus data privatnya.

### Peta Kode

| Lokasi | Peran |
| --- | --- |
| `lib/main.dart` | Inisialisasi aplikasi dan alur pertama kali dibuka. |
| `lib/core/` | Format, normalisasi nama, pemeriksaan NIK, dan keterangan. |
| `lib/data/store.dart` | Penyimpanan data, jurnal, snapshot, dan pemulihan. |
| `lib/data/schema.dart`, `lib/data/migrate.dart` | Skema dan migrasi data. |
| `lib/data/storage.dart`, `lib/data/exchange.dart` | Penyimpanan privat, izin, folder pertukaran, dan cadangan ZIP. |
| `lib/data/spreadsheets.dart` | Impor referensi, ekspor DPS, dan tanda bukti. |
| `lib/data/wilayah.dart`, `lib/data/journal.dart` | Data wilayah dan pembacaan jurnal. |
| `lib/ui/common.dart` | Komponen bersama dan konteks wilayah kerja. |

### Peta Layar

| Berkas | Layar |
| --- | --- |
| `lib/ui/home.dart` | Beranda |
| `lib/ui/lokasi_screen.dart` | Pilih Lokasi Kerja |
| `lib/ui/rt_list_screen.dart` | Daftar Warga |
| `lib/ui/search_screen.dart` | Cari Warga |
| `lib/ui/survey_form.dart` | Warga Baru dan Ubah Data Warga |
| `lib/ui/referensi_screen.dart` | Referensi dan Belum Diinput |
| `lib/ui/import_screen.dart` | Impor Referensi |
| `lib/ui/history_screen.dart` | Riwayat, Duplikat NIK, dan Duplikat Nama |
| `lib/ui/admin_screen.dart` | Ekspor & Pemulihan |
| `lib/ui/snapshot_screen.dart` | Snapshot, Isi Snapshot, dan Bandingkan Snapshot |
| `lib/ui/journal_screen.dart` | Jurnal dan rincian catatan |
| `lib/ui/tanda_bukti_screen.dart` | Tanda Bukti dan Konfigurasi Tanda Bukti |

Antarmuka menggunakan bahasa Indonesia. Pesan kesalahan harus menjelaskan tindakan yang bisa dilakukan pengguna, tanpa menampilkan rincian teknis. Saat melaporkan masalah atau mengirim perubahan, gunakan data contoh dan hindari menyertakan NIK, berkas warga, cadangan, atau log pribadi.

## Data Wilayah dan Lisensi

Nama dan kode wilayah dibundel untuk penggunaan offline dari proyek [WILAYAH oleh Cahya DSN](https://github.com/cahyadsn/wilayah), berlisensi MIT. Asal versi data dicatat di [`third_party/wilayah/SOURCE.txt`](third_party/wilayah/SOURCE.txt), dengan lisensi sumber di [`third_party/wilayah/LICENSE`](third_party/wilayah/LICENSE). Panduan aset wilayah tersedia di [`docs/wilayah.md`](docs/wilayah.md).

Memperbarui aset wilayah tidak otomatis mengubah nama wilayah pada data warga yang sudah disimpan.

Kode aplikasi menggunakan [Lisensi MIT](LICENSE).
