'use strict';
// Opt-in packaged-app qualification. Every write is confined to the explicit
// disposable test home; ordinary launches never enter this path.
const fs=require('node:fs/promises'),path=require('node:path');
const {promisify}=require('node:util'),{execFile}=require('node:child_process');
const {freshConfig,readMachine,writeJSON}=require('./machines.cjs');
const catalog=require('./catalog.cjs'),{paste}=require('./paste.cjs');
const run=promisify(execFile),delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function waitForFinder(engine,home){
  const file=path.join(home,'guest.ppm'),deadline=Date.now()+300000;let stable=0;
  while(Date.now()<deadline){
   await engine.command('screendump',{filename:file});const data=await fs.readFile(file);
   const header=data.subarray(0,200).toString('ascii').match(/^P6\s+(\d+)\s+(\d+)\s+255\s/);
   if(!header)throw new Error('Unexpected guest framebuffer format.');
   const width=Number(header[1]);let dark=0,bright=0,total=0;
   // Sample menu titles only: the empty startup menu's border, Apple and clock
   // must not count as Finder. This region includes File/Edit/View/Special.
   for(let y=3;y<18;y++)for(let x=35;x<Math.min(350,width-100);x++){const i=header[0].length+(y*width+x)*3,rgb=[data[i],data[i+1],data[i+2]];total++;if(Math.max(...rgb)<50)dark++;if(Math.min(...rgb)>170)bright++;}
   if(dark>=180&&bright>=total/2)stable++;else stable=0;
   if(stable>=2){await delay(10000);return;}
   await delay(3000);
  }
  throw new Error('Finder did not appear before the boot deadline.');
 }


async function qualify({window,engines,id,home,imageTool,version}) {
 const report={platform:process.platform,version,checks:[],started:new Date().toISOString()};
 async function check(name,fn){await fn();report.checks.push(name);console.log('PARITY PASS',name);await writeJSON(path.join(home,'parity.json'),report);}
 await check('create/import/config round trip',async()=>{
  const folder=path.join(home,'Created Test.classic');await fs.mkdir(folder);
  const c=freshConfig('Created Test');c.diskSizeGB=1;
  await run(imageTool(),['create','-f','raw',path.join(folder,'disk.img'),'1G'],{windowsHide:true});
  await writeJSON(path.join(folder,'config.json'),c);const m=await readMachine(folder);
  if(m.config.name!==c.name)throw new Error('Created machine did not import.');
  m.config.ramMB=256;await writeJSON(path.join(folder,'config.json'),m.config);
  if((await readMachine(folder)).config.ramMB!==256)throw new Error('Settings did not persist.');
 });
 if(process.env.CLASSICMAC_TEST_LIBRARY==='1')await check('real Library pause/resume/hash/extraction',async()=>{
  const rows=await catalog.loadCatalog(),entry=rows.find(m=>m.id==='mac-os-9.2.1-gxmetal-2.3.0-32gb-v2');
  if(!entry)throw new Error('Clean Library edition is absent.');
  const cache=path.join(home,'cache'),controller=new AbortController();let cancelled=false;
  try{await catalog.download(entry,cache,{signal:controller.signal,progress:p=>{if(p.completed>1048576)controller.abort();}});}catch(e){if(!controller.signal.aborted)throw e;cancelled=true;}
  if(!cancelled)throw new Error('Download pause did not cancel.');
  const folder=await catalog.install(entry,home,'Library Import Test',cache);
  if(!(await readMachine(folder)).config.toolsCDInserted)throw new Error('Library settings were not sanitized.');
 });
 let engine=engines.get(id);if(!engine)throw new Error('Boot engine stopped.');
 await waitForFinder(engine,home);
 await check('boot/display connection',async()=>{
  const evidence=await window.webContents.executeJavaScript('window.classicmacEvidence?.()');
  if(!evidence?.connected||!evidence.canvas)throw new Error('Guest display was not connected.');
 });
 await check('pause/resume',async()=>{await engine.pause();if((await engine.command('query-status')).status!=='paused')throw new Error('Pause failed');await engine.resume();});
 await check('restart/new engine/reconnect',async()=>{
  const previous=engine;await previous.restart();const deadline=Date.now()+60000;
  while((!engines.has(id)||engines.get(id)===previous||!engines.get(id).initialized)&&Date.now()<deadline)await delay(100);
  engine=engines.get(id);if(!engine||engine===previous)throw new Error('Restart did not launch a new engine.');
  await waitForFinder(engine,home);
  const evidence=await window.webContents.executeJavaScript('window.classicmacEvidence?.()');if(!evidence.connected)throw new Error('Display did not reconnect.');
 });
 await check('native guest paste chords',async()=>{
  await engine.hmp('sendkey meta_l-w');await delay(300);
  await paste(engine,'ClassicMacParity');await engine.hmp('sendkey meta_l-o');await delay(1500);
  await engine.hmp('sendkey meta_l-a');await engine.hmp('sendkey meta_l-o');await delay(6000);
  await paste(engine,'ClassicMac parity 4.1\nASCII 123; accents: é ñ',{slow:true});
  await delay(500);
  await fs.writeFile(path.join(home,'parity-desktop.png'),(await window.webContents.capturePage()).toPNG());
 });
 if(process.platform==='linux'&&engine.machine.config.sharedFolderPath)await check('guest 9p host-read and guest-write',async()=>{
  const value=await fs.readFile(path.join(engine.machine.config.sharedFolderPath,'guest-parity.txt'),'utf8');
  if(!value.includes('ClassicMac guest read/write PASS'))throw new Error('Guest shared-file round trip failed.');
 });
 await check('normal guest shutdown',async()=>{
  await engine.hmp('sendkey meta_l-q');await delay(500);await engine.shutdown();
  const deadline=Date.now()+40000;while(engines.has(id)&&Date.now()<deadline)await delay(250);
  if(engines.has(id)||engine.shutdownReason!=='guest-shutdown')throw new Error('Guest did not shut down normally.');
 });
 report.completed=new Date().toISOString();await writeJSON(path.join(home,'parity.json'),report);return report;
}
module.exports={qualify,waitForFinder};
