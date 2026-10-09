// Mechanical resource synchronization; never edits the iOS source catalog.
const fs = require('node:fs');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const catalog = JSON.parse(fs.readFileSync(path.join(root, '../Crest/Localizable.xcstrings'), 'utf8'));
const entries = Object.entries(catalog.strings).map(([key, value]) => [key, value.localizations?.en?.stringUnit?.value]).filter(([, value]) => typeof value === 'string').sort(([a], [b]) => a.localeCompare(b));
const target = path.join(root, 'entry/src/main/ets/core/IOSStrings.ts');
fs.writeFileSync(target, '// Generated from Crest/Localizable.xcstrings. Run npm run sync:strings.\nexport const IOS_ENGLISH: Record<string, string> = ' + JSON.stringify(Object.fromEntries(entries), null, 2) + ';\n');
console.log(`Synchronized ${entries.length} English strings from iOS (read-only source).`);
