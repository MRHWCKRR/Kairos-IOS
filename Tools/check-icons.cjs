const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),assert=require('node:assert/strict');
const root=path.resolve(__dirname,'..');
const icons=path.join(root,'design/icons');
const manifest=JSON.parse(fs.readFileSync(path.join(icons,'icon-manifest.json'),'utf8'));
function files(dir){return fs.readdirSync(dir,{withFileTypes:true}).flatMap(e=>e.isDirectory()?files(path.join(dir,e.name)):[path.join(dir,e.name)]);}
const names=new Set(),sources=files(root).filter(f=>f.endsWith('.swift')&&!f.endsWith('KairosIcon.swift'));
let uses=0;
for(const file of sources){
 const source=fs.readFileSync(file,'utf8');
 assert(!/\b(?:systemName|systemImage)\s*:/.test(source),`Unmigrated SF Symbol call: ${file}`);
 uses+=(source.match(/KairosIcon\(|sharedIcon:/g)||[]).length;
 for(const match of source.matchAll(/(?:KairosIcon\(([^\n)]*)|sharedIcon:\s*([^\n)]*)|icon:\s*("[^"\n]+")|quickAction\("[^"]*",\s*("[^"]*"))/g)){
  for(const string of (match[1]||match[2]||match[3]||match[4]||'').matchAll(/"([^"\n]+)"/g)){
   // Conditional icon expressions also contain row kind names.
   if(['board','occurrence','series'].includes(string[1]))continue;
   names.add(string[1]);
  }
 }
}
for(const name of names)assert(manifest.symbols[name],`Missing semantic mapping: ${name}`);
for(const [name,item] of Object.entries(manifest.symbols)){
 const svg=fs.readFileSync(path.join(icons,item.path));
 assert.equal(crypto.createHash('sha256').update(svg).digest('hex'),manifest.assets[item.slug].sha256,`Source checksum: ${name}`);
 assert(svg.toString().includes('viewBox="0 0 256 256"'),`Incorrect coordinate system: ${name}`);
 for(const target of ['Kairos/Kairos','Kairos/KairosWidgets','KairosWidgets']){
  const asset=path.join(root,target,'Assets.xcassets',item.assetName+'.imageset');
  const contents=JSON.parse(fs.readFileSync(path.join(asset,'Contents.json'),'utf8'));
  assert.equal(contents.properties['preserves-vector-representation'],true);
  assert.equal(contents.properties['template-rendering-intent'],'template');
  assert.deepEqual(fs.readFileSync(path.join(asset,item.slug+'.svg')),svg,`Platform path data differs: ${name}`);
  assert(fs.readFileSync(path.join(root,target,target.endsWith('/Kairos')?'Theme/KairosIcon.swift':'KairosIcon.swift'),'utf8').includes(`"${name}": "${item.assetName}"`),`Missing Swift mapping: ${name}`);
 }
}
console.log(`PASS: ${uses} migrated call sites in ${sources.length} Swift sources; ${names.size} observed semantic names; ${Object.keys(manifest.symbols).length} manifest mappings; source SHA256 and exact asset bytes verified in all three source roots.`);
