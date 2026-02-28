# 🌐 4win VPN - Multi-Protocol VPN Client

<div align="center">

![Version](https://img.shields.io/badge/version-1.4.3-blue)
![Platform](https://img.shields.io/badge/platform-Android-green)
![Flutter](https://img.shields.io/badge/Flutter-3.35.4-02569B?logo=flutter)
![Dart](https://img.shields.io/badge/Dart-3.9.2-0175C2?logo=dart)
![License](https://img.shields.io/badge/license-Private-red)

**Fast, Secure, and Beautiful VPN Client for Android**

[Features](#-features) • [Protocols](#-supported-protocols) • [Installation](#-installation) • [Usage](#-usage) • [Contributing](#-contributing)

</div>

---

## 📱 Overview

4win VPN is a modern, multi-protocol VPN client built with Flutter, offering support for **SSTP**, **Direct DNS**, and **OpenVPN** protocols. Features include automatic server selection, connection monitoring, beautiful animated themes (rain & snow with lightning effects), and a user-friendly interface.

---

## ✨ Features

### 🔐 Security & Privacy
- **Multi-Protocol Support**: SSTP, Direct DNS, OpenVPN (TCP/UDP)
- **Automatic Server Selection**: Fastest server based on ping
- **Kill Switch**: Blocks internet if VPN disconnects (optional)
- **Connection Monitoring**: Real-time speed, ping, duration tracking
- **Secure Credential Storage**: Encrypted local storage

### 🎨 User Experience
- **Beautiful Themes**: 
  - Rain theme with lightning effects ⚡🌧️
  - Snow theme ❄️
  - Dark/Light modes
- **Intuitive UI**: Material Design 3
- **Real-time Stats**: Upload/download speed, connection time
- **Server Ping Test**: Test server response before connecting

### 🌍 OpenVPN Features
- **File Import**: Add .ovpn, .conf, .open config files
- **Credential Management**: Embedded or manual username/password
- **Auto-Detection**: Protocol (TCP/UDP), server, port
- **TCP/UDP Support**: Automatic protocol conversion
- **DNS Configuration**: Auto-adds Google DNS if missing

---

## 🔌 Supported Protocols

| Protocol | Status | Description |
|----------|--------|-------------|
| **SSTP** | ✅ Active | Secure Socket Tunneling Protocol |
| **Direct DNS** | ✅ Active | DNS-based VPN for bypassing restrictions |
| **OpenVPN** | ✅ Active | Industry-standard VPN (TCP & UDP) |

---

## 📦 Installation

### Prerequisites
- **Flutter SDK**: 3.35.4
- **Dart**: 3.9.2
- **Android SDK**: API Level 35
- **Java**: OpenJDK 17.0.2

### Build from Source

```bash
# Clone repository
git clone https://github.com/4win-official/4win-VPN-Source.git
cd 4win-VPN-Source

# Install dependencies
flutter pub get

# Build APK (Release)
flutter build apk --release

# Build App Bundle (for Play Store)
flutter build appbundle --release
```

### Output Files
- **APK**: `build/app/outputs/flutter-apk/app-release.apk`
- **App Bundle**: `build/app/outputs/bundle/release/app-release.aab`

---

## 🚀 Usage

### 1. SSTP Protocol
1. Open app → Select **SSTP** protocol
2. Choose server from list or use **Auto-Select**
3. Tap **Connect**
4. Enter credentials if prompted

### 2. Direct DNS Protocol
1. Select **Direct DNS** protocol
2. Choose DNS server
3. Tap **Connect**
4. No credentials required

### 3. OpenVPN Protocol

#### Adding Config Files
1. Select **OpenVPN** protocol
2. Tap **Settings** → **OpenVPN Configs**
3. Tap **Upload** (📤) button
4. Select `.ovpn`, `.conf`, or `.open` file
5. Enter credentials if not embedded
6. Tap **Add**

#### Connecting
1. Select config from list
2. Tap **Connect**
3. Grant VPN permission if prompted
4. Monitor connection status

#### Ping Test
- Tap **⚡** icon next to config to test server response

---

## 🏗️ Project Structure

```
lib/
├── main.dart                    # App entry point
├── models/                      # Data models
│   ├── vpn_server.dart         # Server model
│   ├── dns_server.dart         # DNS server model
│   └── openvpn_config.dart     # OpenVPN config model
├── providers/                   # State management
│   ├── vpn_provider.dart       # VPN connection state
│   └── theme_provider.dart     # Theme management
├── screens/                     # UI screens
│   ├── home_screen.dart        # Main screen
│   ├── server_list_screen.dart # Server selection
│   ├── settings_screen.dart    # App settings
│   ├── openvpn_configs_screen.dart # OpenVPN management
│   └── theme_selection_screen.dart # Theme picker
├── services/                    # Backend services
│   ├── vpn_service.dart        # SSTP VPN
│   ├── dns_service.dart        # DNS VPN
│   ├── openvpn_connection.dart # OpenVPN handler
│   ├── openvpn_service.dart    # OpenVPN config manager
│   └── server_service.dart     # Server management
└── widgets/                     # Reusable widgets
    ├── rain_animation.dart     # Rain theme with lightning
    └── snow_animation.dart     # Snow theme
```

---

## 🔧 Configuration

### OpenVPN Config Requirements

#### Supported Formats
- `.ovpn` (OpenVPN config)
- `.conf` (Configuration file)
- `.open` (Alternative format)

#### Required Fields
```
client
dev tun
proto tcp-client  # or udp
remote <server> <port>
<ca>
...
</ca>
```

#### Optional Embedded Credentials
```
<auth-user-pass>
username
password
</auth-user-pass>
```

#### Auto-Added Settings
The app automatically adds these settings if missing:
```
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4
persist-key
persist-tun
nobind
resolv-retry infinite
```

For **TCP configs**, also adds:
```
connect-retry-max 3
connect-retry 5
```

---

## 📊 Technical Details

### Dependencies
```yaml
# Core
flutter: sdk
dart: ^3.9.2

# VPN Protocols
sstp_flutter: ^1.3.0
openvpn_flutter: ^1.3.3

# Storage
shared_preferences: 2.5.3

# Network
connectivity_plus: 6.1.5
network_info_plus: 6.1.4
http: 1.5.0

# UI/UX
provider: 6.1.5+1
file_picker: 8.3.7
url_launcher: 6.3.2
permission_handler: 11.4.0
```

### Permissions (Android)
```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
<uses-permission android:name="android.permission.CHANGE_NETWORK_STATE" />
<uses-permission android:name="android.permission.ACCESS_WIFI_STATE" />
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" />
```

---

## 🐛 Debugging

### ADB Logs
```bash
# Clear logs
adb logcat -c

# Filter VPN-related logs
adb logcat | grep -E "(OpenVPN|VPN|flutter)"
```

### Common Issues

#### TCP Connection Fails
- **Cause**: Missing `tcp-client` directive
- **Solution**: App auto-converts `proto tcp` → `proto tcp-client`

#### DNS Resolution Fails
- **Cause**: Missing DNS settings
- **Solution**: App auto-adds Google DNS

#### AUTH_FAILED
- **Cause**: Credentials not found
- **Solution**: Ensure credentials in config or enter manually

#### Connection Timeout
- **Cause**: Server unreachable or firewall
- **Solution**: Run Ping Test, try different server

---

## 🤝 Contributing

### Reporting Issues
1. Check existing issues first
2. Provide clear description
3. Include ADB logs if applicable
4. Specify device model & Android version

### Code Contributions
1. Fork repository
2. Create feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push branch (`git push origin feature/amazing-feature`)
5. Open Pull Request

### Coding Standards
- Follow Dart/Flutter style guide
- Use `flutter analyze` before committing
- Add comments for complex logic
- Test on real devices

---

## 📝 Changelog

### v1.4.3 (Current)
- ✅ Fixed TCP protocol detection and connection
- ✅ Auto-add DNS settings (Google DNS 8.8.8.8, 8.8.4.4)
- ✅ Added essential OpenVPN settings (persist-key, persist-tun, nobind)
- ✅ TCP-specific retry settings
- ✅ Lightning effects for rain theme ⚡
- ✅ Separate OpenVPN settings page
- ✅ Improved protocol display in UI

### v1.6.0 → v1.4.3
- Reverted version number per project requirements
- Enhanced connection stability
- Better error messages

---

## 📄 License

**Private Project** - All rights reserved by 4win Team.

This is a proprietary project. Unauthorized copying, distribution, or modification is prohibited.

---

## 👥 Team

**4win Official Team**

- GitHub: [@4win-official](https://github.com/4win-official)
- Repository: [4win-VPN-Source](https://github.com/4win-official/4win-VPN-Source)

---

## 🙏 Acknowledgments

- **Flutter Team**: Amazing framework
- **OpenVPN Community**: Open-source VPN protocol
- **nizwar/openvpn_flutter**: Flutter OpenVPN plugin
- **Material Design 3**: Beautiful UI components

---

## 📞 Support

For support, issues, or feature requests:
- Open an issue on GitHub
- Contact: 4win Official Team

---

<div align="center">

**Made with ❤️ using Flutter**

⭐ Star this repo if you found it helpful!

</div>
