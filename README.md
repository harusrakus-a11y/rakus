# 🚀 RAKUS SCRIPT | Premium VPS Installer

Selamat datang di panduan instalasi resmi **Rakus Script**. Untuk memastikan script berjalan dengan lancar dan maksimal, silakan ikuti panduan persiapan dan instalasi di bawah ini secara berurutan.

---

### ⚠️ Persyaratan Awal (Prerequisites)

Sebelum melakukan instalasi apa pun di dalam VPS, pastikan Anda telah menyelesaikan dua langkah wajib berikut:

🌐 1. Pointing Domain ke IP VPS
Pastikan domain yang akan Anda gunakan sudah di-pointing secara benar ke Alamat IP VPS Anda.
> **Contoh konfigurasi pointing:**
> 
> <img width="774" height="446" alt="Pointing Domain" src="https://github.com/user-attachments/assets/2b8d89a9-fb02-4e6c-8b76-92493ee86df4" />

🛡️ 2. Pendaftaran IP VPS
Pastikan Alamat IP VPS Anda telah didaftarkan dan berstatus aktif pada sistem kami.
> **Contoh pendaftaran IP:**
> 
> <img width="1033" height="362" alt="Register IP" src="https://github.com/user-attachments/assets/092b5fca-824c-48e2-ae97-18fd8c15f724" />

---

 ⚙️ Persiapan OS (Ubuntu / Debian)

Sebelum memasang script, sistem operasi pada VPS harus diperbarui dan dilengkapi dengan paket dasar yang dibutuhkan. Jalankan perintah berikut secara berurutan:

**Langkah 1: Pembaruan Sistem (Update & Upgrade)**

```
apt-get update && apt-get upgrade -y && apt dist-upgrade -y && update-grub
```

Langkah 2: Pemasangan Paket & Mulai Ulang (Reboot)

```
apt install curl jq wget screen build-essential -y && reboot
```

#<b>⚡ 1. Instalasi Script Rakus
Setelah VPS kembali menyala dan Anda berhasil login ulang, jalankan satu baris perintah di bawah ini untuk memulai proses instalasi otomatis:

```
wget -q https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/install && chmod +x install && ./install
```
</b>

Masukan Nama VPS :
<img width="883" height="254" alt="image" src="https://github.com/user-attachments/assets/060c633a-ddd3-4fdd-872a-a574d31f114b" />

Masukan Nama Domain Yang sudah di pointing :
<img width="885" height="192" alt="image" src="https://github.com/user-attachments/assets/13749588-46bf-4a7a-8d13-f6694951f9d5" />

Pilih Yang tanda merah ENTER :
keep the local version currently installed 
<img width="1077" height="522" alt="image" src="https://github.com/user-attachments/assets/c9e3e0fc-d14d-444e-8505-2d8381e7d94b" />

Setelah prosses install selesai REBOOT VPS Dengan ketik Y lalu ENTER
<img width="754" height="297" alt="image" src="https://github.com/user-attachments/assets/249349ec-7d2a-4cc3-a7ca-e8720dbe7696" />

MASUK KEMBALI KE VPS DENGAN PORT : 200
<img width="704" height="114" alt="image" src="https://github.com/user-attachments/assets/0b3d795b-5670-4279-bd86-58390fb59722" />


🚀 SCRIPT TELAH BERHASIL DI INSTALL 🚀
<img width="447" height="568" alt="image" src="https://github.com/user-attachments/assets/c0eaa5a3-410f-42f3-8bea-0ec3e2252e0d" />




🔄 2. Pembaruan (Update) Script Rakus
Bagi Anda yang sudah menginstal script ini sebelumnya dan hanya ingin melakukan pembaruan (update) ke versi terbaru, silakan jalankan baris perintah berikut:

```
cd /root
rm -f update.sh
wget https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/update.sh && chmod +x update.sh && ./update.sh

```
