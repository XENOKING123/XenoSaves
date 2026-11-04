const { app } = require('electron');
const path = require('node:path');

const packaged = app.isPackaged;
const projectRoot = packaged
  ? process.resourcesPath
  : path.resolve(__dirname, '..');

const pythonDir = path.join(projectRoot, 'poc');
const dataDir = path.join(projectRoot, 'data');
const oracleElf = path.join(pythonDir, 'ncdt_oracle', 'ncdt_oracle_server.elf');

function pythonBin() {
  if (process.platform === 'win32') {
    const bundled = path.join(projectRoot, 'python', 'python.exe');
    try { require('node:fs').accessSync(bundled); return bundled; } catch {}
    return 'python';
  }
  if (process.platform === 'darwin') {
    const bundled = path.join(projectRoot, 'python', 'bin', 'python3');
    try { require('node:fs').accessSync(bundled); return bundled; } catch {}
  }
  return 'python3';
}

module.exports = { projectRoot, pythonDir, dataDir, oracleElf, pythonBin, packaged };
