const { app } = require('electron');
const path = require('node:path');

const packaged = app.isPackaged;
const resourceRoot = packaged
  ? process.resourcesPath
  : path.resolve(__dirname, '..');

const pythonDir = path.join(resourceRoot, 'poc');
const dataDir = path.join(resourceRoot, 'data');
const oracleElf = path.join(pythonDir, 'ncdt_oracle', 'ncdt_oracle_server.elf');

// Python cwd must be writable and outside the asar virtual FS.
// resourcesPath on Windows contains app.asar — mkdir there throws FileExistsError.
const workDir = packaged ? app.getPath('userData') : path.resolve(__dirname, '..');

const defaultDownloads = packaged
  ? path.join(app.getPath('documents'), 'GarlicTransfer')
  : path.join(path.resolve(__dirname, '..'), 'dt_downloads');

function pythonBin() {
  if (process.platform === 'win32') {
    const bundled = path.join(resourceRoot, 'python', 'python.exe');
    try { require('node:fs').accessSync(bundled); return bundled; } catch {}
    return 'python';
  }
  if (process.platform === 'darwin') {
    const bundled = path.join(resourceRoot, 'python', 'bin', 'python3');
    try { require('node:fs').accessSync(bundled); return bundled; } catch {}
  }
  return 'python3';
}

module.exports = { resourceRoot, pythonDir, dataDir, oracleElf, workDir, defaultDownloads, pythonBin, packaged };
