# Pantarlih Kalitorong

Aplikasi Flutter/Dart untuk Android, satu pengguna dan perangkat, sepenuhnya offline. Alat entri data DPS: mengetik sesuai KK asli, dengan saran dari data lama bila diimpor. Tidak menghitung umur dan tidak menentukan kelayakan warga.

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
- Kapitalisasi tombol: aksi utama dan destruktif HURUF BESAR (SIMPAN, HAPUS, BANGUN ULANG DATABASE), aksi sekunder atau pembatal kapital kalimat (Batal, Tutup, Coba minta izin lagi).
- Judul AppBar selalu nama halaman (Beranda, Daftar RT, Ketik nama, Input survei, Riwayat, Impor referensi, Ekspor & pemulihan). Tanggal dan hitungan berada di badan halaman, bukan di judul.
- Penggabung bagian teks memakai titik tengah dengan spasi (` · `), konsisten di seluruh layar.

## Penggunaan

1. Instal APK (Android 7.0+) dan buka aplikasi. Tidak ada izin yang diminta saat membuka. Izin akses berkas (Android 11+: “Izinkan akses untuk mengelola semua file”, Android 7–10: izin penyimpanan biasa) baru diminta saat pertama kali ekspor Excel, membuat cadangan, atau impor.
2. Impor referensi bersifat opsional. Bila ada workbook lama, pilih sheet `RT 03`, `RT 04`, dan `RT 05` satu per satu. Jangan impor `REKAP`. Kolom dipetakan di layar. Impor ulang diperbolehkan. Ada menu hapus semua referensi.
3. Saat pertama dibuka, pilih Provinsi → Kabupaten/Kota → Kecamatan → Desa/Kelurahan, atau ketik manual, atau lewati. RT/RW tetap diketik petugas (data Kemendagri berhenti di desa). Pergantian RT/RW membuat snapshot di dalam aplikasi, dan bila izin berkas sudah ada, juga bundel cadangan plus Excel otomatis di folder publik. Beranda menampilkan jumlah baris dan jumlah tanpa NIK per RT, tanpa persen atau target.
4. Daftar RT adalah layar utama. Tambah di akhir, tombol + di bawah baris untuk sisip, tahan gagang untuk geser, geser kiri untuk hapus. Nomor di ekspor mengikuti urutan ini.
5. Ketik nama minimal 3 karakter. Bagian SUDAH DIINPUT membuka baris yang sudah ada. Bagian REFERENSI mengisi field tanpa menyimpan relasi. TAMBAH BARU selalu dapat ditekan. Jalur tanggal lahir menampilkan semua kecocokan, RT aktif lebih dulu.
6. Isi nama dulu, lalu NIK, JK, tempat/tanggal lahir. NIK boleh kosong. NIK yang bukan 16 digit, tanggal/JK yang tidak cocok, dan NIK duplikat hanya peringatan dan tetap bisa disimpan. Keterangan teks bebas, tidak dikelompokkan atau dinilai.
7. Riwayat menampilkan 20 input terakhir. Jurnal menampilkan semua catatan perubahan per hari dan bisa mengembalikan versi lama seorang warga. Ekspor membuat DPS per RT atau gabungan, plus DUPLIKAT_NIK dan TANPA_NIK. Tidak ada file pending atau konflik RT. Berbagi selalu memerlukan aksi dan konfirmasi eksplisit.

## Lokasi dan keamanan data

Data aplikasi berada di penyimpanan privat aplikasi dan tidak membutuhkan izin apa pun:

```text
pantarlih.db           SQLite (WAL)
journal/               JSONL append-only, per tanggal WIB, tidak pernah dihapus
snapshot/              20 snapshot terbaru, yang tertua dirotasi
import/raw/            file sumber utuh; subfolder unik per percobaan
import/parsed/         sel sebelum normalisasi + pemetaan sheet
import/ready/          record hasil normalisasi
recovered/             database lama dan laporan baris jurnal rusak
```

Folder publik `Documents/Pantarlih<Desa>_<kode>/` hanya untuk pertukaran dengan dunia luar dan hanya disentuh setelah pengguna memberi izin berkas:

```text
ekspor/                hasil ekspor pengguna, satu subfolder per ekspor
ekspor/otomatis/       Excel saat pindah RT/RW, 10 terbaru
cadangan/              cadangan_<stamp>.zip berisi snapshot + seluruh jurnal, 10 terbaru
impor/                 tempat menaruh workbook lama agar mudah ditemukan
```

Data privat ikut hilang saat aplikasi dihapus. Cadangan di folder publik tidak, dan setiap bundel bisa dipulihkan karena memuat jurnal lengkap. Folder tidak terenkripsi. Lindungi HP dengan kunci layar dan salin folder cadangan lewat USB ke media aman. Aplikasi tidak meminta INTERNET, tidak menyimpan foto KK, dan menonaktifkan Android auto-backup. Aplikasi lain yang dipilih pada dialog bagikan dapat mengunggah berkas atas tindakan pengguna.

Workbook pribadi di `data-exel/` diabaikan Git dan tidak dibundel ke APK. Impor membutuhkan file di perangkat. Tes workbook asli berjalan bila file tersedia lokal; tes sintetis tetap berjalan tanpa data pribadi.

## Ketahanan dan keputusan implementasi

- Satu penulis terserialisasi, satu transaksi SQLite per aksi. Event lengkap (termasuk null) di-flush ke JSONL sebelum SQLite.
- Startup memutar ulang event jurnal yang belum ada di database. Jika database hilang, ia dibangun ulang. Pemulihan eksplisit membangun kandidat terlebih dulu dan memindahkan DB lama beserta sidecar WAL/SHM ke `recovered`.
- Snapshot dan jurnal bisa dibuka di aplikasi. Layar Snapshot menampilkan isi tiap snapshot (jumlah warga, tanpa NIK, posisi jurnal), bisa dilihat, dibandingkan dengan data sekarang, dan dipulihkan. Layar Jurnal menelusuri catatan per hari, memutar ulang jurnal ke database uji (PERIKSA), mengembalikan versi lama seorang warga, dan membatalkan hapus.
- Pulihkan snapshot menulis event `RESTORE` yang memuat id event terakhir di snapshot. Replay berjalan dua pas: pas pertama mengumpulkan rentang id yang dibatalkan oleh setiap `RESTORE`, pas kedua melewatinya. Startup dan `rebuild()` menghasilkan keadaan yang sama dengan hasil pemulihan, bukan mengulang diam-diam event yang sudah dibatalkan.
- Pulihkan dari cadangan memakai berkas `cadangan_<stamp>.zip` dari folder publik. Database dan jurnal sekarang dipindahkan ke `recovered`, pasangan dari bundel dipasang, lalu jurnal bundel diputar ulang.
- Baris JSONL rusak dilaporkan dan dilewati. Pemulihan tidak dapat mengembalikan informasi yang hilang dari jurnal rusak; periksa laporan sebelum melanjutkan pendataan.
- NIK kosong dan NIK bukan 16 digit tetap dapat disimpan. Panjang, tanggal, JK, dan duplikat hanya peringatan.
- `urut_sort` sparse kelipatan 1000. Sisip memakai titik tengah. Bila celah habis, renumber otomatis ke 1000, 2000, 3000. Nomor NO di ekspor adalah posisi, bukan nilai tersimpan.
- Referensi read-only di aplikasi, tanpa relasi ke `warga`, tanpa unique constraint. Boleh kotor dan diimpor berulang.
- Normalisasi `ABDURROHMAN` mengikuti algoritme: `abdurohman`. Penggabungan huruf menggunakan `replaceAllMapped`, karena Dart tidak mengekspansi `$1` pada `replaceAll`.
- `excel` 4.x tidak menangani worksheet relationship absolut dan inline-string kosong dari openpyxl. Salinan parsing di memori dinormalkan; byte sumber tetap utuh di arsip.
- Pack wilayah Kemendagri dibundel sebagai `assets/wilayah.db` (baca-saja, bukan data pengguna). Tidak masuk jurnal JSONL dan tidak ikut `rebuild()`. Pilihan desa pengguna tersimpan sebagai snapshot di tabel `lokasi`.

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
