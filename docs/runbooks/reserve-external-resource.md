# Reserve External Resource

```bash
sudo platform-v2 inventory reserve   --name=bachvan   --application=wordpress   --domain=bachvan.com.vn   --http-port=8083   --path=/opt/bachvan   --note="External WordPress site. Reserve HTTP port only."
```

Kiểm tra:

```bash
platform-v2 inventory reserved
platform-v2 inventory validate
```
