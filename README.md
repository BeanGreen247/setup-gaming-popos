# setup-gaming-popos.sh

Automate the setup of a gaming-ready Pop!_OS system with popular tools, performance tweaks, and optional WineHQ support.

## Features

* Enables the `universe` repository automatically.
* Installs essential gaming tools:
  * Steam (Flatpak optional)
  * Lutris
  * ProtonUp-Qt (Flatpak)
  * MangoHud
  * GameMode
  * Vulkan tools
  * OBS Studio
  * vkBasalt
  * 32-bit libraries for Steam/Wine compatibility
* Optional WineHQ repository for Wine + vkd3d packaged builds.
* Checks package availability to skip missing packages.
* Configures recommended system services and kernel tuning for gaming performance.

## Requirements

* Pop!_OS (tested on 22.04 / 23.04)
* `sudo` / root privileges

## Usage

1. Clone or download this repository:

   ```bash
   git clone https://github.com/BeanGreen247/setup-gaming-popos
   cd setup-gaming-popos/
   ```

2. Edit the configuration section in the script to select which tools to install:

   ```bash
   # Example:
   INSTALL_LUTRIS=true
   INSTALL_PROTONUP_FLATPAK=true
   INSTALL_WINEHQ=false
   AUTO_UPDATE=false
   ```

3. Run the script as root:

   ```bash
   sudo bash setup-gaming-popos.sh
   ```

4. Reboot if necessary (drivers, kernel, or major package updates).

## Notes

* If packages are skipped, run:

  ```bash
  sudo apt update && sudo bash setup-gaming-popos.sh
  ```
* To use WineHQ (Wine + vkd3d packaged builds), set `INSTALL_WINEHQ=true` and re-run the script.
* Flatpak is installed automatically if ProtonUp-Qt is enabled.

## Recommended System Tweaks

The script sets some system parameters for better gaming performance:

```text
vm.swappiness=10
vm.vfs_cache_pressure=50
fs.inotify.max_user_watches=524288
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
```

## License

MIT License
