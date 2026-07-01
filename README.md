# RAKUS SCRIPT VPS INSTALL

### SEBELUM INSTALL POINTING DOMAIN IP VPS KAMU DAHULU contoh :
<img width="774" height="446" alt="image" src="https://github.com/user-attachments/assets/2b8d89a9-fb02-4e6c-8b76-92493ee86df4" />


### SEBELUM INSTALL PASTIKAN DAHULU IP VPS TELAH DI DAFTARKAN

<img width="1033" height="362" alt="image" src="https://github.com/user-attachments/assets/092b5fca-824c-48e2-ae97-18fd8c15f724" />


### BEFORE INSTALL OS UBUNTU/DEBIAN  RAKUS
1.

```
apt-get update && apt-get upgrade -y && apt dist-upgrade -y && update-grub 
```

2.

```
 apt install curl jq wget screen build-essential -y && reboot
```

### INSTALL SCRIPT  RAKUS


<pre><code> wget -q https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/install && chmod +x install  && ./install 
</code></pre>



## 2. UPDATE SCRIPT RAKUS

```
cd root
rm update.sh
wget https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/update.sh && chmod +x update.sh && ./update.sh
```


