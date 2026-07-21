# 🚀 RAKUS SCRIPT | Pemasang VPS Premium

Selamat datang ke panduan pemasangan rasmi Rakus Script. Bagi memastikan script berjalan dengan lancar dan pada tahap optimum, sila ikuti panduan persediaan dan pemasangan di bawah mengikut urutan.
---

### ⚠️ Keperluan Asal (Prerequisites)

Sebelum memulakan sebarang pemasangan di dalam VPS, pastikan anda telah menyelesaikan dua langkah wajib ini:

🌐 1. Halakan Domain ke IP VPS (Pointing Domain)
Pastikan domain yang akan anda gunakan sudah dihalakan dengan betul ke Alamat IP VPS anda.
> **Contoh konfigurasi halaan (pointing):**
> 
> <img width="774" height="446" alt="Pointing Domain" src="https://github.com/user-attachments/assets/2b8d89a9-fb02-4e6c-8b76-92493ee86df4" />

🛡️ 2. Pendaftaran IP VPS
Pastikan Alamat IP VPS anda telah didaftarkan dan berstatus aktif di dalam sistem kami.PAUTAN KEBENARAN AKSES: https://github.com/harusrakus-a11y/ijin/blob/main/akses
> **Contoh pendaftaran IP:**
> 
> <img width="1033" height="362" alt="Register IP" src="https://github.com/user-attachments/assets/092b5fca-824c-48e2-ae97-18fd8c15f724" />

---

 ⚙️ Persediaan OS (Ubuntu / Debian)

Sebelum memasang script, sistem operasi (OS) pada VPS mestilah dikemas kini dan dilengkapi dengan pakej asas yang diperlukan. Jalankan arahan (command) berikut mengikut urutan:

**Langkah 1: Kemas Kini Sistem (Update & Upgrade)**

```
apt-get update && apt-get upgrade -y && apt dist-upgrade -y && update-grub
```

Langkah 2: Pemasangan Pakej & Mula Semula (Reboot)

```
apt install curl jq wget screen build-essential -y && reboot
```

#<b>⚡ 1. Pemasangan Script Rakus
Selepas VPS dihidupkan semula dan anda berjaya log masuk (login) kembali, jalankan satu baris arahan di bawah untuk memulakan proses pemasangan automatik:

```
wget -q https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/install && chmod +x install && ./install
```
</b>

Masukkan Nama VPS :
<img width="883" height="254" alt="image" src="https://github.com/user-attachments/assets/060c633a-ddd3-4fdd-872a-a574d31f114b" />

Masukkan Nama Domain Yang Telah Dihalakan (Pointing) :
<img width="885" height="192" alt="image" src="https://github.com/user-attachments/assets/13749588-46bf-4a7a-8d13-f6694951f9d5" />

Pilih Pilihan Yang Bertanda Merah Kemudian Tekan ENTER :
keep the local version currently installed 
<img width="1077" height="522" alt="image" src="https://github.com/user-attachments/assets/c9e3e0fc-d14d-444e-8505-2d8381e7d94b" />

Setelah proses pemasangan selesai, MULA SEMULA (REBOOT) VPS dengan menaip Y kemudian tekan ENTER :
<img width="754" height="297" alt="image" src="https://github.com/user-attachments/assets/249349ec-7d2a-4cc3-a7ca-e8720dbe7696" />

LOG MASUK KEMBALI KE VPS MENGGUNAKAN PORT : 200

<img width="704" height="114" alt="image" src="https://github.com/user-attachments/assets/0b3d795b-5670-4279-bd86-58390fb59722" />

🚀 SCRIPT TELAH BERJAYA DIPASANG! 🚀

<img width="447" height="568" alt="image" src="https://github.com/user-attachments/assets/c0eaa5a3-410f-42f3-8bea-0ec3e2252e0d" />




🔄 2. Kemas Kini (Update) Script Rakus
Bagi anda yang sudah memasang script ini sebelum ini dan hanya mahu melakukan kemas kini (update) ke versi terkini, sila jalankan baris arahan berikut:

```
cd /root
rm -f update.sh
wget https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/update.sh && chmod +x update.sh && ./update.sh

```


## 🎥 Video Tutorial Lengkap

Untuk panduan visual langkah demi langkah yang lebih mudah difahami, sila tonton video tutorial pemasangan VPS Debian ini.
*(Klik gambar di bawah untuk memainkan video)*

<div align="center">
  <a href="https://youtu.be/fb1Q07iT42w" target="_blank">
    <img src="https://img.youtube.com/vi/fb1Q07iT42w/maxresdefault.jpg" alt="TUTORIAL LENGKAP INSTALLASI VPS DEBIAN" width="800" style="border-radius: 10px; box-shadow: 0 4px 8px rgba(0,0,0,0.2);">
  </a>
</div>
