'use strict';
// Cross-platform real-host qualification against disposable public fixtures.
const fs=require('node:fs/promises'),path=require('node:path');
const {spawn,execFile}=require('node:child_process'),{promisify}=require('node:util');
const {createHash,randomUUID}=require('node:crypto');
const {createReadStream,createWriteStream}=require('node:fs');
const {pipeline}=require('node:stream/promises'),{Readable}=require('node:stream');
const run=promisify(execFile);
(async()=>{
 const exe=path.resolve(process.argv[2]),out=path.resolve(process.argv[3]),probe=path.resolve(process.argv[4]);await fs.mkdir(out,{recursive:true});
 const supplied=process.env.CLASSICMAC_TEST_FIXTURE;
 let fixture=supplied?path.resolve(supplied):path.join(out,'Parity Mac.classic');
 if(!supplied){
 const archive=path.join(out,'fixture.tar.gz');
 if(!await fs.access(archive).then(()=>true,()=>false)){
  const r=await fetch('https://mcchord.net/classicmac/mac-os-9.2.1-ati-32gb-v4.tar.gz');if(!r.ok)throw new Error('Fixture download failed');
  await pipeline(Readable.fromWeb(r.body),createWriteStream(archive));
 }
 const hash=createHash('sha256');for await(const part of createReadStream(archive))hash.update(part);
 if(hash.digest('hex')!=='0e2449c5444ee77fb919fc31c52745b438e3972944cbf4cc3d206d19d3775e48')throw new Error('Fixture hash mismatch');
 await fs.mkdir(fixture);await require('../src/catalog.cjs').extract(archive,fixture,{installedBytes:34359738942,diskCapacityBytes:34359738368});
 }
 const file=path.join(fixture,'config.json'),c=JSON.parse(await fs.readFile(file,'utf8'));
 Object.assign(c,{id:randomUUID(),name:'ClassicMac Parity OS 9',machineFamily:'powerMacG4',graphicsCard:process.env.CLASSICMAC_TEST_ATI?'atiRadeon':'standard',width:640,height:480,depth:32,sound:false,networking:true,toolsCDInserted:true,tabletInput:true,bootFromCD:false});
 for(const key of ['sharedFolderPath','cdImagePath','floppyImagePath'])delete c[key];
 const home=path.join(out,'home');await fs.mkdir(home);
 if(process.platform==='linux'){c.sharedFolderPath=path.join(home,'shared');c.sharedVolumeName='Shared Files';await fs.mkdir(c.sharedFolderPath);await fs.writeFile(path.join(c.sharedFolderPath,'host-parity.txt'),'ClassicMac host fixture\n');}
 await fs.writeFile(file,JSON.stringify(c));await fs.writeFile(path.join(home,'library.json'),JSON.stringify([fixture]));
 const env={...process.env,CLASSICMAC_TEST_HOME:home,CLASSICMAC_TEST_START:c.id,CLASSICMAC_TEST_PARITY:'1',CLASSICMAC_TEST_LIBRARY:process.env.CLASSICMAC_TEST_SKIP_LIBRARY?'0':'1',CLASSICMAC_TEST_TOOLS_IMAGE:probe};
 delete env.CLASSICMAC_TEST_CYCLE;delete env.CLASSICMAC_TEST_SCREENSHOT;delete env.CLASSICMAC_RUNTIME;delete env.CLASSICMAC_MAC_APP;
 const child=spawn(exe,['--disable-gpu'],{env,stdio:['ignore','pipe','pipe']}),log=createWriteStream(path.join(out,'app.log'));child.stdout.pipe(log);child.stderr.pipe(log);
 await new Promise((resolve,reject)=>{
  const timer=setTimeout(()=>{if(process.platform==='win32')run('taskkill',['/pid',String(child.pid),'/t','/f']).catch(()=>{});else child.kill();reject(new Error('Qualification timed out'));},900000);
  child.once('error',e=>{clearTimeout(timer);reject(e);});child.once('exit',code=>{clearTimeout(timer);code===0?resolve():reject(new Error('App exited '+code));});
 });
 const report=JSON.parse(await fs.readFile(path.join(home,'parity.json'),'utf8'));if(!report.completed)throw new Error('Qualification did not finish');
 console.log(JSON.stringify(report,null,2));
})().catch(e=>{console.error(e);process.exitCode=1;});
