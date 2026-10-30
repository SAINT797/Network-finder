# Network Finder

A lightweight Windows Wi-Fi network picker and basic recovery helper. It scans nearby Wi-Fi networks through Windows WLAN services, asks for a password when needed, and asks Windows to save/connect to the selected network. A working Wi-Fi adapter and driver are still required; this app cannot replace Wi-Fi hardware or repair a physically failing adapter.

## Requirements

- Windows 10 or 11
- A working Wi-Fi adapter with its driver enabled
- Windows PowerShell 5.1, Windows WLAN AutoConfig, and the built-in NetAdapter PowerShell module

## Run

Extract the files to a folder and double-click **Launch Network Finder.bat**. Select a network and press **Connect**, or double-click the network. A secured network prompts for its password. Close/minimize the window to leave the small tray icon available; right-click the tray icon and choose **Exit** to quit. Connecting is handled by Windows, so quitting this app does not disconnect Wi-Fi.

## Repair and diagnostics

Before the first scan, the app checks whether WLAN AutoConfig is running and whether a recognized physical Wi-Fi adapter is disabled. If either condition is detected, it offers to launch **Repair-Wifi.ps1** with Windows UAC administrator approval. The elevated helper restarts WLAN AutoConfig and cycles the physical Wi-Fi adapter. You can also use **Repair Wi-Fi (Admin)** at any time. Adapter cycling briefly interrupts any existing connection. UAC approval is required; the app cannot elevate silently.

The **Windows diagnostics** button tries to launch Microsoft's built-in Network Adapter diagnostic. If the legacy troubleshooter is unavailable on your Windows version, it opens Settings' Troubleshoot page instead. You can then select the network adapter troubleshooter there.

Enable **Restart WLAN service on every app launch** to save a preference that restarts WLAN AutoConfig whenever Network Finder starts. Windows UAC administrator approval is required on each launch where this option is enabled. This option restarts the WLAN service only; use **Repair Wi-Fi (Admin)** to restart both the service and the adapter. Disable the checkbox to stop automatic restarts. The setting is stored in `%APPDATA%\NetworkFinder\settings.json`.

These repairs are best-effort. They may help when Windows' WLAN service or adapter state is stuck, but cannot guarantee recovery from driver corruption, a hardware fault, or an adapter that Windows no longer detects. Review the Wi-Fi adapter and driver in Device Manager if problems continue.

## Reconnect at sign-in

Windows normally auto-connects to saved Wi-Fi profiles when **Connect automatically** is enabled. The app creates profiles with auto-connect enabled. To optionally open Network Finder at each sign-in, right-click `Install Startup Shortcut.ps1` and choose **Run with PowerShell**. This is not required for Windows to reconnect.

## Notes

The source files are only a few KB and require no bundled runtime or installer. The saved source ZIP is far below 15 MB. For secured networks, the password is written briefly into a temporary WLAN profile XML file so Windows can import it; the app deletes the file after import. Use only networks you are authorized to access.

## Troubleshooting

- If no networks appear, ensure Wi-Fi is enabled, airplane mode is off, and the Windows WLAN AutoConfig service and adapter driver are working.
- If Windows requests administrator approval, approve only if you want the requested WLAN service or Wi-Fi adapter restart. With automatic restart enabled, expect an approval prompt on each app launch.
- If connection fails, verify the password and security type. Windows may display a notification with more detailed status.
- If the app's icon/status does not reflect connectivity, Windows still owns the actual connection; check the Windows network flyout.

## License

MIT; see [LICENSE](LICENSE).
