# C2M 🚀
![Free](https://img.shields.io/badge/Price-100%25%20Free-brightgreen.svg) ![No Ads](https://img.shields.io/badge/Ads-No%20Ads-blue.svg)


## You can minimize an application window on macOS simply by clicking the application's icon on the Dock!

<img width="700" height="410" alt="dock-demo" src="https://github.com/user-attachments/assets/39973abc-b046-4bf7-bb14-e4b3a120824b" />
<img width="380" height="304" alt="menu-demo" src="https://github.com/user-attachments/assets/738d474c-e81f-4e7a-9ef9-2f1b6bfdf728" />

## 📥 Download
Download the latest version for macOS (`.dmg`) at the section [GitHub Releases](https://github.com/MrZero5671/C2M/releases/latest).

## ✨ Key features
- Minimize the application window when clicking its icon on the Dock
- Open at login
- Supported language: Vietnamese (English support coming soon)

## 💻 System requirements
1.Supports Apple Silicon (M-series), does not support Intel-based Macs.

2.Mac OS 27 or later (current version)
> ⚠️ Working on lowering the requirement to (MacOS 13) — update expected next week
> If you are using macOS 13, 14, 15, or 16 and want to try it out early, you can build it yourself from the source code using Xcode (see the build instructions below) and manually adjust the **Minimum Deployments** setting to the corresponding version

## ⬇️ How to download
1. Download file `C2M.dmg`.
2. Open file `C2M.dmg` and drag it into the Applications folder

## ⚠️ First launch warning

Since this app is not signed with a paid Apple Developer certificate, macOS will show a warning like *"C2M cannot be opened because the developer cannot be verified"* on first launch. To open it anyway:

1. **Right-click** (or Control-click) on `C2M.app` → select **Open**.
2. Click **Open** again in the confirmation dialog.

After this, the app will open normally every time.

## 🔑 Required permission

On first launch, C2M will ask for **Accessibility** permission — this is required for the Dock-click minimize feature to work.

- **macOS 26/27**: System Settings > Privacy & Security > **Device Control and Data Access**
- **macOS 13/14/15**: System Settings > Privacy & Security > **Accessibility**

## ⚙️ Building for macOS 13 / 14 / 15 / 26

This app currently ships with a Minimum Deployment Target of macOS 27, but the code itself doesn't rely on anything exclusive to that version — the only modern API in use is `SMAppService` (for Launch at Login), which has been available since **macOS 13 Ventura**. If you're on macOS 13, 14, 15, or 26 and want to run C2M on your machine right now instead of waiting for the next release, you can easily build it yourself:

1. **Clone or download this repository** and open `C2M.xcodeproj` in Xcode (Xcode 15 or newer is recommended).
2. Select the **C2M** project in the navigator, then select the **C2M** target.
3. Go to the **General** tab and find **Minimum Deployments**. Lower it to match your macOS version (e.g. `13.0` for Ventura, `14.0` for Sonoma, `15.0` for Sequoia).
4. Build and run (`⌘R`) directly, or archive it (`Product > Archive`) to export a standalone `.app` you can move to `/Applications` and run independently of Xcode.
5. On first launch, grant the app **Accessibility** permission when prompted — this is required for the Dock-click minimize feature to work. On macOS 27, this setting has been moved under **Device Control and Data Access**; on earlier versions, it's under **Privacy & Security > Accessibility**.

That's it — no other code changes should be needed. If you run into a compiler error tied to a specific API after lowering the deployment target, feel free to open an issue and I'll take a look.

## 📄 License

This project is licensed under the [MIT License](LICENSE).


