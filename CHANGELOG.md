# Changelog

## 0.7.0 — 23 September 2026

- Versi aplikasi kembali ditampilkan di pojok kanan atas Beranda.
- Pemulihan cadangan dan snapshot lebih aman, termasuk saat proses terputus atau terjadi kegagalan penyimpanan.
- Impor ZIP dan Excel dibatasi agar berkas yang rusak atau terlalu besar tidak menghabiskan memori perangkat.
- Penyimpanan warga dan pembersihan draf dilakukan dalam satu transaksi. NIK referensi yang tersamar atau terlalu panjang tetap diperiksa tanpa menyambungkan atau memotong angka.
- Perbaikan penghapusan referensi, pembatasan pergantian desa, perlindungan cadangan Android, serta pesan pemulihan yang lebih jelas.
- README dilengkapi alur penggunaan, model data, dan rencana pengembangan.

## 0.6.0 — 19 September 2026

### Ditambahkan

- **Promosi referensi menjadi warga.** Baris referensi kini bisa dijadikan data warga langsung: satu ketukan dari layar Belum Diinput, atau sekaligus satu RT lewat menu Promosikan Referensi di Daftar Warga dengan konfirmasi hitungan terlebih dahulu. Baris hasil promosi masuk di akhir daftar mengikuti urutan berkas sumber, dan baris referensi aslinya tetap tersimpan sebagai jejak sumber.
- **Layar Belum Diinput.** Daftar baris referensi RT aktif yang belum punya padanan di data warga. Padanan dihitung dari nama yang dinormalisasi, ditambah tanggal lahir bila keduanya terisi. Layar kosong berarti RT tersebut selesai. Tiap baris bisa diperiksa lewat formulir terisi atau langsung dipromosikan.
- **Draf otomatis formulir Warga Baru.** Isian formulir tersimpan sebagai draf 500 ms setelah jeda mengetik. Bila aplikasi mati sebelum Simpan, formulir berikutnya menawarkan Lanjutkan atau Buang. Draf hanya berlaku untuk formulir warga baru pada RT/RW yang sama dan dibersihkan setelah simpan berhasil.
- **CI GitLab.** Setiap push menjalankan pemeriksaan statis `dart analyze lib/`.

### Diubah

- Kartu referensi di Cari Warga kembali hanya sebagai saran yang membuka formulir terisi. Promosi satu ketukan dipusatkan di layar Belum Diinput agar alur Tambah Warga tidak berubah.
- README menandai kolom `grup_id` sebagai cadangan yang sengaja tidak dipakai.
- Ekspor temuan (duplikat NIK, duplikat nama, tanpa NIK) tidak lagi jadi berkas terpisah, melainkan sheet tambahan di dalam berkas DPS yang sama. Tiap sheet hanya muncul bila kategorinya berisi.

### Perbaikan

- Tombol Buka pada berkas Excel hasil ekspor di layar Ekspor & Pemulihan.
