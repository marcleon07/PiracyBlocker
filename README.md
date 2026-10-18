# PiracyBlocker

A simple website blocker for Windows. It blocks piracy sites and Kremlin propaganda sites, while Russian services like Yandex, VK, Mail.ru, Gosuslugi and Russian banks keep working.

I made it for my granddad's PC, so it's meant to be set up once and then forgotten about. It uses the Windows hosts file, so there is nothing running in the background and no browser extension. Once installed, it updates its lists by itself.

## Install

1. Download this repo (**Code → Download ZIP**) and unzip it.
2. Double-click **`Install.bat`** and click **Yes** when Windows asks.
3. Restart the web browser.

Run **`Status.bat`** to check it's working. Run **`Uninstall.bat`** to remove everything.

## What it does

- Blocks about 2,850 sites: torrents, cracked games, illegal streaming and MP3 sites, plus RT, Sputnik, RIA, TASS, Channel One, NTV and similar outlets.
- Downloads an up-to-date piracy list from [The Block List Project](https://github.com/blocklistproject/Lists) at every startup and every day at 12:00.
- Never blocks anything in `allowlist.txt`, including its subdomains, even if a downloaded list contains it.
- Keeps the last good copy of a list if a download fails, so nothing gets unblocked by accident.
- Only changes its own marked section of the hosts file and keeps a backup (`hosts.piracyblocker.bak`).

## Customising

Each list is a plain text file with one domain per line. You don't need to add `www.` versions; they are blocked automatically.

| File | Purpose |
| --- | --- |
| `blocklist*.txt` | Sites to block. Every file with this name is used |
| `allowlist.txt` | Sites that must never be blocked |
| `sources.txt` | Online lists to download, for example a Gist with your own propaganda list |

After editing, run `Install.bat` again to apply the changes.

## Limitations

- It only blocks the exact addresses listed, so sites that move to a new domain get through until they're added.
- It can't block content inside Telegram, VK, YouTube or similar platforms.
- An administrator, a VPN or a custom DNS setup can bypass it. If the person using the PC shouldn't be able to turn it off, use a standard Windows account for them.
