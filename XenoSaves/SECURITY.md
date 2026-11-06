# Security

How XenoSaves keeps users and the platform safe.

## Nothing secret ships in the app
The only credential inside the downloaded app is the **public** Supabase key — the same key
the website already serves to every browser. It cannot change or delete anyone's data.

Everything that could be abused is **server-side** and checks your account on every request:
- the save-transfer worker key,
- publishing a save to the collection,
- approving or declining a shared save,
- moderation (ban / mute / delete).

So there is nothing in the download for anyone to extract and misuse. Taking a copy of the
app apart does not give anyone the power the owner has.

## Tamper protection
- Windows executables and the installer are **code-signed**.
- The program files are **integrity-checked** at launch (Electron fuses + asar integrity);
  a modified copy refuses to run.
- The app cannot be relaunched as a plain Node process or attached to with a debugger to
  read memory, by design (fuses: run-as-node off, inspect off, NODE_OPTIONS off).

## Updates
Updates are delivered as signed packages and verified before installing. Only a **newer**
version is ever installed, so a downgrade cannot be forced. An update never interrupts a
save transfer.

## Your data
Saves are read locally. Your original files are never modified — edits are written to a
separate copy. A save becomes public only after you choose to share it **and** an admin
reviews it. Private uploads under review are stored in a private bucket only you and
reviewers can read.

## Reporting a problem
Found a security issue? Please contact XENO KING privately (Discord / the website) rather
than opening a public issue, so it can be fixed before it is known.
