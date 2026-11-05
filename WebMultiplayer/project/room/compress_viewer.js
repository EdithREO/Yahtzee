'use strict';
const fs=require('node:fs'),path=require('node:path'),zlib=require('node:zlib');
for(const name of ['index.wasm','index.pck','index.js']){
 const file=path.resolve(__dirname,'../../public/viewer',name),data=fs.readFileSync(file);
 const packed=zlib.gzipSync(data,{level:9});fs.writeFileSync(file+'.gz',packed);
 console.log(`${name}: ${data.length} -> ${packed.length} bytes`);
}
