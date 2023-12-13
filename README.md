# What does this script do?
Supported distros Ubuntu, Debian.
- Automatically generates and configures SSH authentication keys (optional). The private key will be saved under directory  `./gensshkey`
- Changes the SSH login port (optional).
- Installs [Hextrixtool](https://hetrixtools.com/) monitoring (optional).
- Installs [Docker](https://docs.docker.com/engine/install/debian/) (optional).
- Sets the timezone to Asia/Bangkok.
- Executes update and upgrade commands.

# How to use?

```bash
wget -O  secure-basic.sh https://raw.githubusercontent.com/haiphamhoang/vps-basic-secure/main/secure-basic.sh
chmod +x secure-basic.sh
./secure-basic.sh
```

