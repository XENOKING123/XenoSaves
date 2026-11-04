# GarlicTransfer

**Alpha release — 0.1.0**

GarlicTransfer is an Electron application for downloading PS5 save containers to a PC and uploading selected saves back to a console through Sony's Data Transfer protocol. It supports local PPR oracles on a jailbroken PS5 and volunteer workers through HTOS.

This is research software. Back up your saves before using Upload. Upload can overwrite or remove console save data, and the workflow intentionally asks you to delete the original saves first.

## Features

- Console discovery over DDP (`SRCH`) with firmware display.
- Per-console profiles keyed by host ID; each profile has separate metadata, manifests, and saves.
- Offline PS4/PS5 title names from [PlayStation-Titles](https://github.com/andshrew/PlayStation-Titles).
- A persistent console-to-PC session: browse once, then download one or more saves without re-entering Data Transfer mode.
- Single-user, multi-save upload selection using previously downloaded metadata.
- Filtered upload metadata and save-only transfer behavior based on a captured working transfer.
- Automatic source power signal and optional clean `DisconnectPS5` reboot after downloading.
- Local or volunteer PPR oracle support.

Console-to-PC downloading has been exercised on 13.60. Protocol version handling for 13.x and 14.x is implemented from live responses. Other firmware versions use the inferred major-version mapping and remain unverified.

## Requirements

- Node.js 18 or newer and npm.
- Python 3.10 or newer.
- The Python packages in `requirements.txt`.
- A PS5 and PC on the same local network.
- An HTOS worker/API key for the volunteer oracle, or a jailbroken PS5 for a local oracle.
- On Linux, `pkexec`/PolicyKit for the Upload backend to bind TCP ports 1004/1005 and UDP port 1006. Only the backend requests elevation; Electron runs as the normal user. On Debian/Ubuntu, the package is `policykit-1`.

## Install

```bash
git clone https://git.etawen.dev/earthonion/GarlicTransfer.git
cd GarlicTransfer
npm install
python3 -m venv .venv
. .venv/bin/activate
pip install -r requirements.txt
```

Activate the Python environment before starting the app so its `python3` can import `cryptography`:

```bash
. .venv/bin/activate
npm start
```

On Linux, if `pkexec` is missing:

```bash
sudo apt install policykit-1
```

Do not run the whole Electron application as root. Upload will display a PolicyKit authentication prompt when privileged ports are required.

## Configuration

Open **Settings** in the app and choose **Save settings** to create `config.ini`. This file may contain your worker key and is deliberately excluded from git. `config.example.ini` documents the available settings.

Oracle choices:

- **Volunteer workers:** enter the HTOS server URL and a worker/API key from the server's Contribute page. The server must support `ppr_derive`; the corresponding worker implementation is in garlic-worker 1.1.7 or newer.
- **Local oracle:** disable volunteer workers and enter the jailbroken console's address. GarlicTransfer can deploy the included `poc/ncdt_oracle/ncdt_oracle_server.elf` through the console's payload listener on port 9021. The oracle listens on port 9022.

The profile root defaults to `dt_downloads`. Downloads are separated as:

```text
dt_downloads/
  <console-host-id>/
    metadata.db
    manifest.json
    <save-entry-id>/
      manifest.json
      <save containers>
```

## Download saves

1. Start GarlicTransfer and click **Discover consoles**.
2. Select the source console, then click **Browse console saves**.
3. If asked, press the console power button until it beeps and release.
4. Select one or more saves and click **Download selected**, or use the per-save Download button.
5. Keep the session open for more selections, or choose **Finish and reboot console**.

Downloaded entry folders contain the save containers and a manifest with paths, sizes, SHA-256 hashes, and GFP5 headers.

## Upload saves

1. Download metadata and the save containers first. Upload selections come from the selected console's existing metadata profile.
2. Click **Upload selected saves**.
3. Select one user and one or more downloaded saves.
4. Delete **all selected original saves** on the client console.
5. Confirm in GarlicTransfer and authenticate the backend if prompted.
6. On the console, open **Settings → System → System Software → Data Transfer**, press **Continue**, select **GarlicTransfer**, then **Start transfer**.

The source power signal is sent automatically after one second. Upload generates a filtered metadata database containing one user and only the selected save entries.

## Firmware mapping

The DDP `system-version` determines both the command protocol and power-body firmware value:

| Firmware | Command protocol |
| --- | --- |
| 1.02 | `0x010` |
| 13.60 | `0x130` |
| 14.22 | `0x140` |
| 15.00 | `0x150` |
| 21.00 | `0x210` |

Only 13.x/14.x are live-verified. The remaining mappings are inferred from the major-version pattern.

## Development checks

```bash
npm run check
python3 -m py_compile poc/dt_backend.py poc/dt_download.py poc/dt_metadata.py poc/dt_source.py poc/dt_discovery.py
```

## Title data

PS4 and PS5 title data is bundled from [andshrew/PlayStation-Titles](https://github.com/andshrew/PlayStation-Titles) under the MIT license. Its license and source notice are in `data/PlayStation-Titles-LICENSE.txt`.
