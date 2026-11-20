# 🌟 Global Remote DNS

Merged all protocols' **Remote DNS** servers into one field in Global settings. VLESS now supports Cloudflare DNS servers and hijacks them into related DoH servers within worker.  
The Remote DNS only accepts IPv4 and IPv6 now to boost up performance specially for **VLESS**.

> [!IMPORTANT]
> The worker scripts get updated in the background after you update to this version. however it needs to connect to the internet, You can confirm worker update by checking `Settings` > `VLESS` > `Cloudflare accounts`, there will be a manual update button in case the update was not successful.

## 💡 Bug fixes and improvements

- Made Remote DNS global, improved VLESS DNS performance and added Cloudflare DNS support to.
- Updated worker minification setup.

**Full Changelog**: https://github.com/bia-pain-bache/BPB-VPN/compare/v1.2.1...v1.2.2

![GitHub Downloads (all assets, specific tag)](https://img.shields.io/github/downloads/bia-pain-bache/BPB-VPN/v1.2.2/total)
