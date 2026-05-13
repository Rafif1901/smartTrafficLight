# Traffic Light System with Adjustable Modes and Ambulance Detection

## Kelompok berapa gw lupa

- ojan
- rafif
- danish alfa
- salsabila

## Fitur

- lampu merah pada umumnya
- lampu kuning kelap kelip (mode mati, kaya di kelapa dua jam 7 malem keatas)
- merahin semua jalur kalau ngedeteksi suara ambulans
- deteksi ambulans dengan algoritma Goertzel (bentuk efisien dari discrete fourier transform untuk suatu titik frekuensi)
- jam real-time
- Toggle mode lampu di jam tertentu

## Batasan

- Asumsi sirine ambulans bolak-balik di 800 dan 1500 Hz
- Asumsi sirine ambulans fast yelp (indikasi bawa pasien darurat)
- Mengabaikan efek doppler
- Asumsi pengendara taat aturan semua

## Perhitungan Konstanta Goertzel

F_sample = 8000 Hz
N = 100 
F_target1 = 800 Hz
F_target2 = 1500 Hz

k_1 = (800 * 100) / 8000 = 10
k_2 = (1500 * 100) / 8000 = 18

w1 = (2pi * k_1) / N = 0.628
w2 = (2pi * k_2) / N = 1.131

coeff1 = 2cos(w1) = 2cos(0.628) = 1.618
coeff2 = 2cos(w2) = 2cos(1.131) = 0.851

### ubah koefisien menjadi integer 32-bit dengan format Q14

coeff1 = 1.618 * 16384 = 26510
coeff2 = 0.851 * 16384 = 13943

> ubah ke bentuk awal: shift kanan 14-bit
