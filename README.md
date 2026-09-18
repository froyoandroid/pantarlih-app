# TilikSuara · pendataan DPS offline

Aplikasi Flutter/Dart untuk Android, satu pengguna dan perangkat, sepenuhnya offline. Alat bantu pencatatan data pemilih: mencatat sesuai dokumen kependudukan asli, didukung pencarian pintar dan saran data referensi. Tidak menghitung umur dan tidak menentukan kelayakan hak pilih warga.

## Jalankan / build

Toolchain yang terbukti membangun (output `flutter --version`):

```text
Flutter 3.47.4 • channel stable
Framework • revision 9584c6713b • 2026-09-10
Dart 3.13.3
```

UI memakai API stabil (`ReorderableListView.onReorder` dan `DropdownButtonFormField.value`) supaya mesin dengan Flutter lebih lama tetap dapat mengompilasi. `pubspec.yaml` membatasi Dart `>=3.3.0 <4.0.0`. Java 21, Android SDK 36, NDK 27.0.12077973. Dependensi dikunci di `pubspec.lock`.

```sh
flutter pub get
flutter analyze
flutter test --concurrency=1
flutter run -d 127.0.0.1:5555       # pengembangan: build debug (default), mendukung hot reload
flutter build apk --release --split-per-abi   # produksi
```

Build debug (`flutter run`) adalah default untuk pengembangan — ukuran besar (~69 MB) karena JIT, jangan dipakai untuk dipasang di lapangan.

APK produksi: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` (~19 MB, HP arm64 modern; `armeabi-v7a` untuk HP lama). Build release lokal menggunakan signing key debug Android; cocok untuk sideload/perangkat tunggal, bukan publikasi Play Store. Gunakan keystore produksi yang dipertahankan untuk distribusi dan pembaruan jangka panjang. Jangan uninstall untuk memperbarui; install APK dengan tanda tangan yang sama di atas versi lama.

## Konvensi UI

- Semua teks antarmuka berbahasa Indonesia dan tidak mengandung titik koma (`;`).
- Jangan gunakan huruf kapital semua (ALL CAPS). Kapitalisasi judul dan tombol menggunakan huruf kapital di tiap awal kata (Title Case, contoh `Tambah Warga`, `Daftar Warga`, `Cari Warga`, `Warga Baru`, `Simpan`, `Hapus`, `Buat File Excel`). Aksi pembatal atau sekunder menggunakan Title Case atau kapital kalimat (`Batal`, `Tutup`, `Coba minta izin lagi`).
- Judul AppBar selalu nama halaman dalam Title Case (`Beranda`, `Daftar Warga`, `Cari Warga`, `Warga Baru` / `Ubah Data Warga`, `Riwayat`, `Referensi`, `Impor Referensi`, `Ekspor & Pemulihan`). Tanggal dan hitungan berada di badan halaman, bukan di judul.
- Penggabung bagian teks memakai titik tengah dengan spasi (` · `), konsisten di seluruh layar.
- Format RT dan RW selalu menggunakan dua digit angka dengan garis miring berjarak (`RT 03 / RW 02`).

## Penggunaan

1. Instal APK (Android 7.0+) dan buka aplikasi. Tidak ada izin yang diminta saat pertama kali membuka aplikasi. Izin akses berkas (Android 11+: “Izinkan akses untuk mengelola semua file”, Android 7–10: izin penyimpanan biasa) baru diminta saat pertama kali mengekspor Excel, membuat berkas cadangan, atau mengimpor rujukan.
2. Impor referensi bersifat opsional. Bila memiliki berkas rujukan lama dalam format Excel atau CSV, pilih sheet yang relevan satu per satu (misalnya `RT 03`, `RT 04`, dan `RT 05`). Jangan mengimpor sheet rekapitulasi. Kolom dipetakan langsung di layar. Impor ulang diperbolehkan kapan saja. Halaman Referensi dapat menampilkan isi setiap berkas yang telah diimpor serta menyediakan opsi pembersihan data referensi.
3. Saat pertama kali dibuka, tentukan lokasi kerja: pilih Provinsi → Kabupaten/Kota → Kecamatan → Desa/Kelurahan, atau ketik secara manual, atau lewati untuk diisi kemudian. Wilayah RT dan RW ditentukan langsung oleh petugas sesuai penugasan. Setiap pergantian RT atau RW secara otomatis membuat snapshot di ruang privat aplikasi, serta menulis berkas cadangan zip dan salinan Excel otomatis di folder publik apabila izin berkas telah diberikan. Layar Beranda menampilkan ringkasan jumlah warga dan catatan tanpa NIK per RT secara ringkas dan informatif.
4. Daftar warga merupakan layar utama pendataan. Tekan `Tambah Warga` di sudut kanan atas atau tombol tambah pada celah baris untuk menyisipkan warga baru, tahan ikon urutan untuk mengubah posisi susunan, dan geser kartu ke kiri untuk menghapus. Penomoran pada ekspor Excel mengikuti urutan susunan ini.
5. Cari warga: ketik nama minimal 3 huruf. Bagian `Sudah Diinput` menampilkan data warga yang telah tersimpan pada basis data. Bagian `Referensi` menampilkan saran dari berkas rujukan untuk mempercepat pengisian data baru. Tombol `Tambah Warga` selalu tersedia untuk input langsung. Mode pencarian tanggal lahir menampilkan seluruh kecocokan dengan memprioritaskan RT aktif.
6. Pengisian formulir mengutamakan nama lengkap, NIK, jenis kelamin, serta tempat dan tanggal lahir. NIK boleh dikosongkan apabila belum tersedia pada dokumen. Validasi format NIK (panjang 16 digit, kesesuaian tanggal lahir dan jenis kelamin, serta deteksi NIK terdaftar) berfungsi sebagai pengingat ketelitian tanpa memblokir penyimpanan data. Kolom keterangan mendukung kode cepat (`TMS`, `PD`, `B`, `MD`) maupun catatan bebas.
7. Riwayat menampilkan 20 pencatatan terakhir. Jurnal mencatat setiap perubahan data secara permanen per hari, mendukung pemulihan versi sebelumnya serta pembatalan penghapusan warga. Ekspor menghasilkan berkas Excel DPS per RT maupun gabungan seluruh wilayah kerja, disertai sheet `DUPLIKAT_NIK` dan `TANPA_NIK`. Pembagian berkas ke aplikasi lain selalu memerlukan tindakan dan konfirmasi eksplisit dari pengguna.

## Lokasi dan keamanan data

Data aplikasi berada di ruang penyimpanan privat aplikasi dan tidak membutuhkan izin apa pun:

```text
pantarlih.db           SQLite (WAL)
journal/               JSONL append-only, per tanggal WIB, tidak pernah dihapus
snapshot/              20 snapshot terbaru, rotasi otomatis
import/raw/            berkas sumber utuh; subfolder unik per percobaan
import/parsed/         data sel mentah sebelum normalisasi
import/ready/          data warga hasil normalisasi siap pakai
recovered/             salinan database lama dan laporan baris jurnal rusak
```

Folder publik `Documents/Pantarlih<Desa>_<kode>/` hanya untuk pertukaran berkas dengan perangkat luar setelah pengguna memberikan izin penyimpanan:

```text
ekspor/                hasil ekspor Excel pengguna, satu subfolder per ekspor
ekspor/otomatis/       salinan Excel saat berpindah RT atau RW, 10 berkas terbaru
cadangan/              cadangan_<stamp>.zip berisi snapshot dan seluruh jurnal, 10 berkas terbaru
impor/                 tempat meletakkan berkas rujukan agar mudah ditemukan aplikasi
```

Data privat aplikasi akan terhapus apabila aplikasi dicopot (uninstall). Berkas cadangan di folder publik tetap aman dan dapat dipulihkan kapan saja karena memuat snapshot basis data dan riwayat jurnal lengkap. Berkas cadangan tidak terenkripsi; amankan perangkat Anda dengan kunci layar dan salin folder cadangan secara berkala ke komputer atau media penyimpanan eksternal melalui kabel USB. Aplikasi tidak memerlukan koneksi internet, tidak memuat fitur kamera atau foto dokumen kependudukan, dan menonaktifkan pencadangan otomatis cloud Android.

Berkas rujukan pribadi di `data-exel/` diabaikan oleh Git dan tidak dibundel ke APK. Impor membutuhkan berkas di perangkat. Pengujian dengan berkas rujukan asli berjalan bila berkas tersedia secara lokal; pengujian sintetis tetap berjalan tanpa data pribadi.

## Ketahanan dan keputusan implementasi

- Satu alur penulisan terserialisasi dengan satu transaksi SQLite per aksi. Setiap perubahan ditulis lengkap ke berkas jurnal JSONL sebelum disimpan ke basis data SQLite.
- Saat aplikasi dibuka, sistem memutar ulang catatan jurnal yang belum tercermin di database. Jika database hilang atau rusak, basis data dibangun ulang secara otomatis dari jurnal.
- Layar Snapshot menampilkan daftar salinan database (jumlah warga, tanpa NIK, posisi jurnal), mendukung peninjauan isi, perbandingan perbedaan dengan data aktif, serta pemulihan ke kondisi waktu tertentu.
- Layar Jurnal memungkinkan penelusuran riwayat harian, uji keutuhan data (tombol Periksa), pengembalian versi data warga sebelumnya, dan pembatalan penghapusan warga.
- Pemulihan snapshot mencatat event `RESTORE` yang memuat id event terakhir pada snapshot tersebut. Pemutaran ulang jurnal melompati aksi yang dibatalkan oleh pemulihan sebelumnya secara konsisten.
- Pemulihan dari cadangan menggunakan berkas `cadangan_<stamp>.zip` dari folder publik. Database aktif saat ini diamankan ke folder `recovered` sebelum data cadangan dipasang dan diputar ulang.
- Baris JSONL rusak dilaporkan dan dilewati tanpa menghentikan proses pemulihan.
- NIK kosong maupun NIK yang belum 16 digit tetap dapat disimpan. Peringatan format NIK dan deteksi duplikat berfungsi sebagai pengingat ketelitian.
- Urutan warga (`urut_sort`) menggunakan penomoran renggang kelipatan 1000 sehingga penyisipan warga di antara dua baris dapat dilakukan tanpa mengubah baris lain. Penataan ulang nomor otomatis berjalan saat celah habis.
- Data referensi bersifat hanya-baca di dalam aplikasi, tanpa relasi kaku ke tabel warga aktif, sehingga dapat dimuat ulang atau dibersihkan kapan saja.
- Normalisasi pencarian nama menangani variasi penulisan umum dalam ejaan bahasa Indonesia.
- Pengurai berkas Excel menangani format tabel dan karakter kosong secara tangguh dengan tetap mempertahankan berkas asli di arsip.
- Data wilayah Kemendagri dibundel secara lokal (`assets/wilayah.db`) sebagai referensi statis baca-saja. Pilihan wilayah tersimpan sebagai snapshot di tabel `lokasi` dan tidak terpengaruh jika berkas wilayah diperbarui.

## Data wilayah (Kemendagri)

Sumber: [cahyadsn/wilayah](https://github.com/cahyadsn/wilayah) oleh Cahya DSN, lisensi MIT. Dump yang dibundel mengikuti Kepmendagri No. 300.2.2-2430 Tahun 2025. LICENSE sumber ada di `third_party/wilayah/LICENSE`, SHA dan tanggal unduh di `third_party/wilayah/SOURCE.txt`.

Membangun ulang aset (di desktop, bukan di HP):

```sh
# unduh db/wilayah.sql terbaru ke third_party/wilayah/wilayah.sql
# perbarui SHA di third_party/wilayah/SOURCE.txt dan tool/build_wilayah.dart
dart run tool/build_wilayah.dart
```

Lalu build APK. Nama salinan runtime memuat SHA pendek, jadi pack baru tersalin otomatis tanpa logika versi tambahan.

**Memperbarui pack tidak pernah mengubah data yang sudah tersimpan.** Nama wilayah pada setiap baris warga dan pada tabel `lokasi` adalah snapshot. Sheet INFO pada ekspor membaca snapshot itu, bukan `wilayah.db`.

Opsional: `dart run tool/build_wilayah.dart --prov=33` hanya memasukkan Jawa Tengah. Build penuh adalah bawaan.

## Atribusi

Aplikasi ini memakai kode dan nama wilayah administrasi pemerintahan Indonesia dari proyek WILAYAH (<https://github.com/cahyadsn/wilayah>), Copyright (c) 2017-2025 Cahya DSN, lisensi MIT, sesuai Kepmendagri No. 300.2.2-2430 Tahun 2025.

## Pengujian

Tes meliputi normalisasi, fuzzy matching, tanggal DD-first, NIK sebagai peringatan, impor referensi 504 baris, sisip/geser/renumber, duplikat, replay identik termasuk `urut_sort`, baris jurnal terpotong, database hilang, kegagalan penulisan jurnal, urutan sel Excel, snapshot dan perubahan sesi. Lakukan uji singkat izin, impor, simpan, sisip, ekspor, dan pemulihan di HP sasaran sebelum dipakai di lapangan.
