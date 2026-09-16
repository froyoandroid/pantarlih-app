# WILAYAH.md — Integrasi Data Wilayah Kemendagri

Repo aplikasi : https://gitlab.com/firenza20/pantarlih-app
Sumber data   : https://github.com/cahyadsn/wilayah (MIT)
Basis         : Kepmendagri No. 300.2.2-2430 Tahun 2025 (`db/wilayah.sql`)
Basis kode    : HEAD `fix(13)` saat dokumen ini ditulis, schemaVersion 3 → 4

Dokumen ini adalah lanjutan dari SPEC.md v2.0 dan FIX.md. Seluruh aturan
di sana tetap berlaku.

## 0. Tujuan

Menghapus seluruh hardcode lokasi dari aplikasi. Petugas memilih
Provinsi → Kabupaten/Kota → Kecamatan → Desa/Kelurahan dari data resmi,
dan pilihan itu mengalir ke form, validasi NIK, serta berkas ekspor.

### 0.1 Aturan yang tidak boleh dilanggar

Selain seluruh aturan FIX.md §0:

1. Data wilayah TIDAK PERNAH masuk jurnal JSONL. Yang dijurnal hanyalah
   pilihan pengguna (satu baris `lokasi`), bukan 91.600 baris referensi.
2. `wilayah.db` read-only. Dibuka dengan `readOnly: true`. Tidak pernah
   di-INSERT, UPDATE, atau ikut `rebuild()`.
3. Tidak ada akses jaringan. Seluruh data dibundel sebagai aset.
   Manifest tetap tanpa izin INTERNET.
4. Wilayah tidak boleh memblokir input. Bila desa tidak ditemukan di
   daftar, pengguna wajib tetap dapat mengetik nama desa secara bebas
   dan menyimpan.
5. `keterangan` tetap teks bebas murni.
6. Kolom ekspor tidak berubah. Tetap sepuluh kolom sesuai SPEC §11.1.

## 1. Bentuk data sumber

Tabel tunggal `wilayah (kode, nama)`. Kode bertitik dan hierarkis.
Panjang menentukan level: 2 = provinsi, 5 = kab/kota, 8 = kecamatan,
13 = desa/kelurahan. Induk adalah potongan sebelum titik terakhir.

## 2–11. Tugas

Urutan pengerjaan: W1 → W2 → W3 → W4 → W5 → W6 → W8 → W7 → W10 → W9.

- W1 skrip build `tool/build_wilayah.dart` → `assets/wilayah.db`
- W2 `WilayahRepo` terisolasi, read-only, gagal buka tidak menggagalkan startup
- W3 schemaVersion 4, `kode_wilayah`, tabel `lokasi`, migrateEvent 3→4
- W4 layar pemilihan lokasi, termasuk mode manual
- W5 hapus hardcode KALITORONG / RT 3 / RW 3
- W6 peringatan prefix NIK dari `lokasi.nik_prefix` (bukan penghalang)
- W8 sheet INFO, nama berkas, opsi kop (default mati)
- W7 backfill baris lama, satu event per baris, tidak otomatis
- W10 tampilkan versi pack, atribusi README dan Tentang
- W9 pemilih lokasi saat impor referensi

## 12. Lisensi

Data bersumber dari proyek MIT cahyadsn/wilayah. LICENSE sumber disimpan
di `third_party/wilayah/LICENSE`. Atribusi wajib di README dan di aplikasi.

## 13. Keputusan desain

1. `wilayah.db` database terpisah, bukan tabel di `pantarlih.db`.
2. `wilayah.sql` hanya diparse saat build, tidak di runtime.
3. Simpan kode (`warga.kode_wilayah`) dan snapshot nama (`warga.desa`,
   kolom nama di `lokasi`). Referensi tidak pernah jadi sumber kebenaran.
4. Enam digit pertama NIK adalah kecamatan penerbitan, bukan domisili.
   Peringatan kuning, bukan penghalang.
5. Tidak ada daftar RT/RW dari data Kemendagri. Kode resmi berhenti di
   desa/kelurahan.
