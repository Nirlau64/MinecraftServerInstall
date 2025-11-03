# MinecraftServerInstall

This script automates the setup of a Minecraft server, including support for Forge and Fabric mod loaders.

## Features

* Automatic installation of a Minecraft server for your chosen version.
* Tested with both **Forge** and **Fabric** mod loaders.
* Includes configuration and startup automation.

## Requirements

* A Linux server or VPS with sufficient storage and memory.
* Java (for example, OpenJDK) installed.
* Network access with the server port (default: `25565`) open.

## Installation & Usage

1. Clone this repository or download the script.
2. Adjust the settings inside the script (Minecraft version, mod loader, allocated RAM, etc.).
3. **Important:** Before running the script, move all your mod `.jar` files into the `mods/` folder.
4. Move all configuration files into the `config/` folder as well.
5. Run the script. It will install the selected mod loader, copy mods and configs, and start the server.
6. Connect to your server using its IP address and port.

## Mod Loader Support

* **Forge** – fully tested and working.
* **Fabric** – works **only with the setup script in the `testing` branch**.

## Notes

* Mods and configuration files **must be placed** into their respective folders before running the script.
* Changing mods or configurations afterward may require a full server restart.
* Backups are recommended before installing large mod packs.

## Contact

For issues, feature requests, or contributions, please open an Issue or Pull Request on GitHub.
