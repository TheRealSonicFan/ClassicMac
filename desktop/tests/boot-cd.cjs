'use strict';
// Installed app / installer-CD check using only a newly created test disk.
const fs=require('node:fs/promises'),path=require('node:path');
const {spawn,execFile}=require('node:child_process'),{promisify}=require('node:util');
const {freshConfig}=require('../src/machines.cjs');const run=promisify(execFile);
(async()=>{
 const [exeArg,outArg,isoArg]=process.argv.slice(2),exe=path.resolve(exeArg),out=path.resolve(outArg),iso=path.resolve(isoArg);
 await fs.mkdir(out,{recursive:true});const folder=path.join(out,'Quadra CD Test.classic'),home=path.join(out,'home');await fs.mkdir(folder);await fs.mkdir(home);
 const c=freshConfig('Quadra 800 CD Test','quadra800');Object.assign(c,{ramMB:128,width:640,height:480,depth:8,sound:false,networking:false,cdImagePath:iso,bootFromCD:true,toolsCDInserted:true});
 const tool=path.join(path.dirname(exe),'resources','runtime','bin',process.platform==='win32'?'qemu-img.exe':'qemu-img');
 await run(tool,['create','-f','raw',path.join(folder,'disk.img'),'1G'],{windowsHide:true});
 await fs.writeFile(path.join(folder,'config.json'),JSON.stringify(c));await fs.writeFile(path.join(home,'library.json'),JSON.stringify([folder]));
 const shot=path.join(out,'quadra.png'),env={...process.env,CLASSICMAC_TEST_HOME:home,CLASSICMAC_TEST_START:c.id,CLASSICMAC_TEST_SCREENSHOT:shot,CLASSICMAC_TEST_WAIT:'90000',CLASSICMAC_TEST_AUTOSTOP:'1'};
 for(const k of ['CLASSICMAC_TEST_PARITY','CLASSICMAC_TEST_CYCLE','CLASSICMAC_TEST_TOOLS_IMAGE','CLASSICMAC_RUNTIME','CLASSICMAC_MAC_APP'])delete env[k];
 const child=spawn(exe,['--disable-gpu'],{env,stdio:['ignore','pipe','pipe']}),log=require('node:fs').createWriteStream(path.join(out,'app.log'));child.stdout.pipe(log);child.stderr.pipe(log);
 await new Promise((resolve,reject)=>{const timer=setTimeout(()=>{child.kill();reject(new Error('CD boot timed out'));},180000);child.on('error',reject);child.on('exit',code=>{clearTimeout(timer);code===0?resolve():reject(new Error('App exit '+code));});});
 const display=JSON.parse(await fs.readFile(shot+'.json')),shutdown=JSON.parse(await fs.readFile(shot+'.shutdown.json'));
 if(!display.connected||!display.canvas||!shutdown.cleanShutdown)throw new Error('CD display or shutdown failed');console.log('Quadra CD display and normal shutdown PASS; inspect quadra.png for Finder.');
})().catch(e=>{console.error(e);process.exitCode=1;});
