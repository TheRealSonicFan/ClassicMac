'use strict';
// Same fixed US/MacRoman keyboard plan as the native Mac frontend. Clipboard
// text never becomes HMP syntax. Validate everything before sending any key.
function plan(text) {
  if (typeof text !== 'string') throw new Error('Enter plain text.');
  const chars = [...text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').normalize('NFC')];
  if (!chars.length || chars.length > 8192) throw new Error('Paste between 1 and 8,192 characters at a time.');
  const keys = new Map();
  for (const c of 'abcdefghijklmnopqrstuvwxyz0123456789') keys.set(c, c);
  for (const c of 'ABCDEFGHIJKLMNOPQRSTUVWXYZ') keys.set(c, 'shift-' + c.toLowerCase());
  for (const [a,b,key] of [['`','~','grave_accent'],['-','_','minus'],['=','+','equal'],['[','{','bracket_left'],[']','}','bracket_right'],['\\','|','backslash'],[';',':','semicolon'],["'",'"','apostrophe'],[',','<','comma'],['.','>','dot'],['/','?','slash'],...Array.from('1234567890', (n,i) => [n,'!@#$%^&*()'[i],n])]) {
    keys.set(a,key); keys.set(b,'shift-' + key);
  }
  keys.set(' ','spc'); keys.set('\t','tab'); keys.set('\n','ret');
  const accents = new Map();
  for (const [key,lower,upper,bases] of [['e','áéíóú','ÁÉÍÓÚ','aeiou'],['u','äëïöüÿ','ÄËÏÖÜŸ','aeiouy'],['i','âêîôû','ÂÊÎÔÛ','aeiou'],['grave_accent','àèìòù','ÀÈÌÒÙ','aeiou'],['n','ãñõ','ÃÑÕ','ano']]) {
    [...lower].forEach((c,i) => accents.set(c,['alt-'+key,bases[i]]));
    [...upper].forEach((c,i) => accents.set(c,['alt-'+key,'shift-'+bases[i]]));
  }
  for (const [c,key] of Object.entries({'ç':'alt-c','Ç':'alt-shift-c','å':'alt-a','Å':'alt-shift-a','ø':'alt-o','Ø':'alt-shift-o','ß':'alt-s'})) accents.set(c,[key]);
  return chars.map(c => { const sequence=keys.has(c) ? [keys.get(c)] : accents.get(c); if (!sequence) throw new Error(`Unsupported character U+${c.codePointAt(0).toString(16).toUpperCase()}. Nothing has been pasted.`); return sequence; });
}
async function paste(engine,text,{slow=false,signal,progress=()=>{}}={}) {
  const sequences=plan(text);
  for (const [i,sequence] of sequences.entries()) {
    if (signal?.aborted || engine.exited || engine.paused) throw new Error('Pasting stopped. Text already entered remains in the Mac.');
    for (const key of sequence) {
      const response = await engine.hmp(`sendkey ${key} 1`);
      if (/unknown key|error:|unknown command/i.test(String(response))) throw new Error('The Mac rejected a key chord.');
      await new Promise(resolve=>setTimeout(resolve,slow?125:50));
    }
    progress(i+1,sequences.length);
  }
}
module.exports={plan,paste};
