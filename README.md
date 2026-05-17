# Traffic Light System with Adjustable Modes and Ambulance Detection

## Anggota Kelompok
- Fauzan Arfa Nofiantoro - 2406411793
- Danish Al Fayyadh Sunarta - 2406416951
- Salsabila Maharani Mumtaz - 2406348156
- Muhammad Rafif Batubara - 2406436253

## Table of Contents
- [Introduction](#introduction)
- [Hardware Design and Implementation Details](#hardware-design-and-implementation-details)
- [Software Implementation Details](#software-implementation-details)
- [Test Results and Performance Evaluation](#test-result-and-performance-evaluation)
- [Conclusion and Future Work](#conclusion-and-future-work)

---

## Introduction

### Problem
- Kemacetan lalu lintas sering kali menghambat laju kendaraan darurat seperti ambulans, yang dapat berakibat fatal bagi pasien.
- Sistem lampu lalu lintas konvensional beroperasi dengan siklus statis yang tidak efisien pada malam hari.
- Tidak adanya sistem prioritas otomatis di persimpangan jalan ketika ada kendaraan darurat yang mendekat.

### Solution
- Sistem ini menggunakan arsitektur **Master-Slave** mikrokontroler ATmega328P yang diprogram menggunakan AVR Assembly.
- **Arduino Master** bertugas mengendalikan siklus lampu lalu lintas tiga arah dan mengintegrasikan modul RTC untuk manajemen waktu operasional secara presisi.
- **Arduino Slave** bertugas mendengarkan audio di sekitar persimpangan dan memprosesnya untuk mendeteksi keberadaan pola sirene ambulans tipe *fast yelp* menggunakan algoritma Digital Signal Processing (DSP).
- Ketika sirene terdeteksi, Slave akan mengirimkan sinyal interupsi perangkat keras ke Master untuk mengamankan persimpangan secara instan.

### Main Features
- **Siklus Lampu Lalu Lintas Normal**: Beroperasi mengatur laju kendaraan untuk persimpangan tiga arah (Utara, Selatan, Timur).
- **Mode Malam (Standby)**: Lampu kuning berkedip dapat diaktifkan secara otomatis berdasarkan RTC maupun manual menggunakan switch. Waktu operating dan standby dapat dikonfigurasi secara dinamis melalui UART/Serial Monitor.
- **Deteksi Sirene Ambulans**: Memanfaatkan Algoritma Goertzel untuk mengekstraksi energi frekuensi suara secara jauh lebih efisien dibandingkan Discrete Fourier Transform (DFT) standar.
- **Emergency Override**: Saat pola sirene ambulans valid terdeteksi, Arduino Slave mengirimkan External Interrupt ke Arduino Master sehingga sistem menghentikan siklus traffic light normal dan mengaktifkan kondisi seluruh lampu merah (all-red state) sebagai mode darurat.

### Batasan
- Asumsi sirene ambulans bergantian bolak-balik di frekuensi 800 Hz dan 1500 Hz dengan pola *fast yelp* (indikasi membawa pasien darurat).
- Mengabaikan efek Doppler dari pergerakan kendaraan terhadap frekuensi sirene.
- Asumsi semua pengendara menaati aturan saat mode darurat diaktifkan.

---

## Hardware Design and Implementation Details

Sistem ini mendistribusikan beban kerja secara efisien ke dalam dua unit mikrokontroler.

* **Arduino Master (Traffic Controller):** Mengendalikan susunan LED lampu lalu lintas (Merah, Kuning, Hijau) untuk tiga arah menggunakan PORTB dan PORTD. Terhubung dengan modul RTC via jalur I2C (SDA/SCL) untuk sinkronisasi waktu aktual.
* **Arduino Slave (Siren Detector):** Menggunakan sensor suara mikrofon yang terhubung ke pin ADC. Sistem ini menggunakan Timer0 untuk mengatur laju pengambilan sampel (*sampling rate*) pada tepat 8000 Hz.
* **Jalur Komunikasi:** Menggunakan pin PD2 dari Slave yang dihubungkan ke pin INT0 pada Master. Slave akan menaikkan status pin ini menjadi HIGH (pulsa ~10ms) ketika sirene terkonfirmasi, yang secara langsung memicu interupsi eksternal di Master.

### Komponen

| Komponen | Deskripsi |
| :--- | :--- |
| **2x Arduino Uno (ATmega328P)** | Bertindak sebagai unit Master dan Slave. |
| **Modul RTC (I2C)** | Manajemen waktu *real-time* untuk penjadwalan mode malam. |
| **Sensor Suara Mikrofon** | Menangkap audio lingkungan untuk dianalisis oleh Slave. |
| **LED (Merah, Kuning, Hijau)** | Indikator visual lampu lalu lintas persimpangan. |
| **Resistor** | Pembatas arus untuk memastikan komponen bekerja dalam batas aman. |

**Rangkaian akhir**


---

## Software Implementation Details

Program ditulis menggunakan instruksi tingkat rendah (AVR Assembly) untuk memastikan determinisme dan efisiensi waktu eksekusi yang ketat, hal ini sangat krusial pada rutinitas pemrosesan sinyal digital.

### Algoritma Goertzel pada Slave
Arduino Slave menggunakan Algoritma Goertzel untuk mendeteksi frekuensi target karena algoritma ini jauh lebih hemat siklus komputasi dibandingkan algoritma Fast Fourier Transform (FFT). FFT akan menghitung energi untuk semua rentang frekuensi secara bersamaan, sedangkan Goertzel hanya menghitung tepat pada titik frekuensi spesifik yang dicari (dalam kasus ini, 800 Hz dan 1500 Hz), sehingga mampu menghemat hingga 96% waktu operasi CPU.

Sistem memproses audio dengan parameter perhitungan berikut:
* `f_s` (Sample Rate) = 8000 Hz
* `N` (Window Size) = 100 sampel (jeda 12.5 ms per jendela)
* `f_target1` = 800 Hz
* `f_target2` = 1500 Hz

**Perhitungan Indeks Bin (k):**
* `k_1 = round((800 * 100) / 8000) = 10`
* `k_2 = round((1500 * 100) / 8000) = 19`

**Koefisien Dasar (Floating Point):**
* `omega_1 = (2 * pi * 10) / 100 ≈ 0.6283 rad  -->  coeff_1 = 2 * cos(0.6283) ≈ 1.6180`
* `omega_2 = (2 * pi * 19) / 100 ≈ 1.1938 rad  -->  coeff_2 = 2 * cos(1.1938) ≈ 0.7362`

**Konversi Skala Fixed-Point (Format Q14):**
Karena mikrokontroler ATmega328P tidak mendukung perangkat keras *floating-point*, nilai koefisien dikalikan dengan 2^14 (16384) untuk disimpan dan dioperasikan sebagai integer 16-bit.
* `COEFF_800 = round(1.6180 * 16384) = 26510`
* `COEFF_1500 = round(0.7362 * 16384) = 12063`

Jika Finite State Machine (FSM) mendeteksi transisi lonjakan energi yang memenuhi ambang batas antara target frekuensi 800 Hz dan 1500 Hz secara konsisten (minimal 4 alternasi), status dianggap valid sebagai suara sirene.

### Software Used
![Visual Studio Code](https://img.shields.io/badge/Visual%20Studio%20Code-0078d7.svg?style=for-the-badge&logo=visual-studio-code&logoColor=white)
![Arduino](https://img.shields.io/badge/Arduino_IDE-00979D?style=for-the-badge&logo=arduino&logoColor=white)
![Proteus](https://img.shields.io/badge/Proteus-Simulation-blue?style=for-the-badge&logoColor=white)
![Assembly](https://img.shields.io/badge/Assembly-Language-critical?style=for-the-badge&logoColor=white)

#### flowchart 
**master.S**
<img width="8045" height="2605" alt="master" src="https://github.com/user-attachments/assets/d84e189c-70d4-4b3d-ac11-867f5a280c82" />

**slave.S**
<img width="8191" height="1370" alt="slave" src="https://github.com/user-attachments/assets/0d1bd191-f3a3-47c1-b906-8389a8a1486e" />




---

## Test Result and Performance Evaluation


| Parameter Pengujian | Gambar Rangkaian / Kondisi Fisik | Output Serial Monitor / UART |
| :--- | :--- | :--- |
| **Siklus Normal** |<img width="703" height="430" alt="Screenshot 2026-05-17 155618" src="https://github.com/user-attachments/assets/ae22e4ad-e6d2-4904-aeec-e67ffc23ba8c" />| `Utara: HIJAU - 3 ...` |
| **Transisi Mode Malam (Standby)** |<img width="628" height="432" alt="Screenshot 2026-05-17 155815" src="https://github.com/user-attachments/assets/fd749e34-2457-4c5c-894f-5a14d7945935" />| `Input config: s19.00.00` |
| **Deteksi Sirene Ambulans** |<img width="682" height="362" alt="Screenshot 2026-05-17 155840" src="https://github.com/user-attachments/assets/43993e45-8edb-40ef-8ef8-f0829779393a" />| `Siren detected - Interrupting master...` |

### Performance Evaluation
Sistem berhasil merespons perubahan mode secara real-time berdasarkan RTC maupun konfigurasi serial monitor. Selain itu, interrupt dari modul deteksi sirene dapat melakukan override terhadap operating mode sehingga emergency mode dapat diaktifkan dengan cepat. Pada modul Slave, algoritma pemrosesan DSP yang diimplementasikan melalui operasi *fixed-point* dalam Assembly terbukti dapat mengkalkulasi tingkat energi frekuensi setiap 12.5 milidetik tanpa mengalami *bottleneck*, memberikan sisa *headroom* siklus komputasi yang besar bagi mikrokontroler untuk melakukan interupsi dan operasi I/O UART. Tantangan teknis yang memerlukan perhatian lebih adalah pada aspek sensitivitas perangkat keras mikrofon dan kalibrasi nilai *threshold* (LO dan HI) untuk mencegah indikasi positif palsu (*false-positive*) akibat bising jalanan biasa yang terdeteksi masuk ke dalam frekuensi bin.

---

## Conclusion and Future Work

Sistem "Traffic Light System with Adjustable Modes and Ambulance Detection" berhasil menunjukkan bukti konsep nyata bahwa implementasi pemrosesan sinyal digital (Digital Signal Processing) dan arsitektur respons Master-Slave sangat dimungkinkan pada mikrokontroler 8-bit tanpa harus bergantung pada *library* dari bahasa tingkat tinggi. Hal ini menonjolkan efisiensi dan kecepatan *low-level programming*.

Sistem hanya mendeteksi pola fast yelp 800–1500 Hz, belum mempertimbangkan efek Doppler dan noise lingkungan tinggi dapat mempengaruhi akurasi. Untuk penyempurnaan di masa depan, sistem dapat diperkuat dengan teknologi radio pemancar nirkabel (seperti modul RF atau LoRa) langsung dari unit ambulans ke lampu lalu lintas untuk mengatasi keterbatasan sensor akustik di lingkungan perkotaan yang berpolusi suara tinggi. Manajemen siklus persimpangan juga dapat ditingkatkan menggunakan sensor deteksi visual atau *loop detector* aspal untuk menyesuaikan durasi lampu hijau secara dinamis berdasarkan volume kepadatan antrean.
