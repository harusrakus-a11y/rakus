# RAKUS SCRIPT VPS INSTALL

### BEFORE INSTALL OS UBUNTU/DEBIAN  RAKUS
1.

```
apt-get update && apt-get upgrade -y && apt dist-upgrade -y && update-grub 
```

2.

```
 apt install curl jq wget screen build-essential -y && reboot
```

### INSTALL SCRIPT 


<pre><code> wget -q https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/install && chmod +x install  && ./install 
</code></pre>



## 2. UPDATE 

```
cd root
rm update.sh
wget https://raw.githubusercontent.com/harusrakus-a11y/rakus/refs/heads/main/menu/update.sh && chmod +x update.sh && ./update.sh
```


