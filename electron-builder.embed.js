// electron-builder config for "build.bat embed".
//
// package.json's own "build" section plus one extra resource: the private Python
// runtime placed at resources/python, which electron/paths.cjs pythonBin() prefers
// over a system "python".  Kept as a file rather than a -c.extraResources[4] CLI
// override because electron-builder 24 rejects the array-index form.
const pkg = require('./package.json');

module.exports = {
  ...pkg.build,
  extraResources: [
    ...(pkg.build.extraResources || []),
    {
      from: 'build/python',
      to: 'python',
      filter: ['**/*', '!**/__pycache__/**', '!*.pyc', '!**/*.pdb'],
    },
  ],
};
