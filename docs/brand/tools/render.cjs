const fs = require('node:fs/promises');
const path = require('node:path');
const sharp = require('sharp');
const root = path.resolve(__dirname, '..');
async function main() {
  await fs.mkdir(path.join(root, 'png'), { recursive: true });
  for (const name of await fs.readdir(path.join(root, 'svg'))) {
    if (!name.endsWith('.svg')) continue;
    await sharp(path.join(root, 'svg', name), { density: 144 }).png().toFile(path.join(root, 'png', name.replace('.svg', '@2x.png')));
  }
  const icon = path.join(root, 'svg', 'senlearn-app-icon.svg');
  for (const size of [1024, 512, 180, 120, 60, 40, 32]) {
    await sharp(icon).resize(size,size).removeAlpha().png().toFile(path.join(root,'png',`senlearn-app-icon-${size}.png`));
  }
  await sharp(path.join(root,'svg','senlearn-app-icon-dark.svg')).resize(1024,1024).removeAlpha().png().toFile(path.join(root,'png','senlearn-app-icon-dark-1024.png'));
  const logo = await sharp(path.join(root,'svg','senlearn-logo-horizontal.svg')).flatten({background:'#F7F5ED'}).png().toBuffer();
  await fs.writeFile(path.join(root,'png','senlearn-logo-preview.png'),logo);
  const mono = await sharp(path.join(root,'svg','senlearn-logo-monochrome.svg')).flatten({background:'#F7F5ED'}).png().toBuffer();
  await fs.writeFile(path.join(root,'png','senlearn-logo-monochrome-preview.png'),mono);
  // Review composition uses the exact export assets and outlined text.
  const get = async name => (await fs.readFile(path.join(root,'svg',name),'utf8')).replace(/<\?xml[^?]*\?>/,'');
  const sheet = `<svg xmlns="http://www.w3.org/2000/svg" width="1600" height="1040" viewBox="0 0 1600 1040"><defs><clipPath id="icon-mask"><rect x="64" y="64" width="520" height="520" rx="115"/></clipPath></defs><rect width="1600" height="1040" fill="#EEECE3"/><g clip-path="url(#icon-mask)"><g transform="translate(64 64) scale(.508)">${await get('senlearn-app-icon.svg')}</g></g><rect x="64" y="64" width="520" height="520" rx="115" fill="none" stroke="#E0DED3" stroke-width="2"/><g transform="translate(660 88) scale(.75)">${await get('senlearn-logo-horizontal.svg')}</g><path d="M660 465 H1515" stroke="#CED8CB"/><g transform="translate(710 490) scale(.42)">${await get('senlearn-mark.svg')}</g><g transform="translate(1130 490) scale(.42)">${await get('senlearn-mark-monochrome.svg')}</g><rect x="64" y="648" width="520" height="320" rx="30" fill="#172E26"/><g transform="translate(82 702) scale(.44)">${await get('senlearn-logo-reverse.svg')}</g></svg>`;
  await fs.writeFile(path.join(root,'brand-preview.svg'),sheet);
  await sharp(Buffer.from(sheet)).png().toFile(path.join(root,'brand-preview.png'));
  console.log('Rendered vector exports and previews.');
}
main().catch(e=>{console.error(e);process.exit(1)});
