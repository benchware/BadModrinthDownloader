<img src="New Project.png" style="max-width:1000px;display:block;width:100%;border-radius:5px;margin-bottom:7px;">

# BadModrinthDownloader
An terrible coded Modrinth downloader that can download in bulks and it's fucking coded in Powershell.
It supports Linux, too. Have fun!
## Features
- Download mods in bulk from Modrinth
- Download modpacks!
- Written entirely in **PowerShell**
- Minimal dependencies
## Installation
No installation required. Just download the downloader and run it with PowerShell.
## How to run?
1. Navigate to the repository and click "Code" and then click "Download ZIP" or go to the latest release and download it.

2. Write your mods you need to download in the file `mods.txt`. You don't need a whole Visual Studio IDE for this. Just copy the links of the mods you want to install into that file or write it's slugs to it. **Remember: Every mod you want to download should be on its own line. No extra characters, just plain text, each on a new row.**
3. Then open PowerShell or Windows Terminal on your machine and you need to run `set-executionpolicy remotesigned` and pressing `Y`.
4. Run the file called `MRDL.ps1` by opening PowerShell and typing the command `./MRDL.ps1`. It should download your mods in Modrinth. If it doesn't work, try running it again or do Step 3.
5. Your mod or modpack will proceed downloading. Note that the speed depends on your internet, storage,...
6. Your mods should be here. Move it to your server mods directory, or client whatever.

## License
This project is licensed under the GNU General Public License (GPL) v3.0.
You are free to use, modify, and distribute this software under the terms of the GPL v3.0.

For more information, see [GNU General Public License](https://www.gnu.org/licenses/gpl-3.0.en.html).

# If you found any bugs, please scream at me on the bug tracker.

