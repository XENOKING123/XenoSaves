const fs = require('node:fs');
const path = require('node:path');

const titles = new Map();

for (const filename of ['PS5_Titles.tsv', 'PS4_Titles.tsv']) {
  const contents = fs.readFileSync(path.join(__dirname, '..', 'data', filename), 'utf8');
  for (const line of contents.split(/\r?\n/).slice(1)) {
    const [titleId, , name] = line.split('\t', 3);
    if (titleId && name) titles.set(titleId.split('_', 1)[0].toUpperCase(), name);
  }
}

function titleName(titleId) {
  return titles.get(String(titleId || '').toUpperCase()) || 'Unknown title';
}

module.exports = { titleName };
