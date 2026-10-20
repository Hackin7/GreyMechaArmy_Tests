import {readFile,writeFile,mkdir,mkdtemp,rm} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
import {createHash} from 'node:crypto';
import {tmpdir} from 'node:os';
import path from 'node:path';
import {parsePCB,nodes,node,numbers,property,rounded,pointTransform,boardOutline,photoRegistration,circleThroughPoints} from './pcb-geometry.mjs';

const pcbPath=process.argv[2];
if(!pcbPath)throw Error('Usage: npm run sync:simulator-board -- /path/to/greybadge_pcb.kicad_pcb [kicad-cli]');
const cli=process.argv[3]??process.env.KICAD_CLI??(process.platform==='win32'?'C:/Program Files/KiCad/10.0/bin/kicad-cli.exe':'kicad-cli');
const root=new URL('../',import.meta.url),destination=new URL('public/simulator/board/',root);
const source=await readFile(pcbPath,'utf8'),board=parsePCB(source),outline=boardOutline(board);
const footprints=nodes(board,'footprint');
const netNames=new Map(nodes(board,'net').map(net=>[net[1],net[2]]));
const netOf=pad=>{const n=node(pad,'net');return n?.[2]??netNames.get(n?.[1]);};
const buttonsPins=['B4','A5','B5','A6','B6','D12','C12'],ledPins=['C3','D3','C4','D4','C5','D5','C6','D6'];
function footprintData(fp) {
  const at=numbers(fp,'at'),reference=property(fp,'Reference');
  const body=fp.filter(item=>Array.isArray(item)&&['fp_line','fp_rect','fp_poly'].includes(item[0])&&node(item,'layer')?.[1]==='F.Fab');
  const points=body.flatMap(item=>[numbers(item,'start'),numbers(item,'end'),...nodes(node(item,'pts')??[],'xy').map(p=>p.slice(1).map(Number))]).filter(p=>p.length===2);
  const fallback=reference.startsWith('SW')?[4.6,4.6]:[1.6,.8];
  const width=points.length?Math.max(...points.map(p=>p[0]))-Math.min(...points.map(p=>p[0])):fallback[0];
  const height=points.length?Math.max(...points.map(p=>p[1]))-Math.min(...points.map(p=>p[1])):fallback[1];
  return {reference,footprint:fp[1],layer:node(fp,'layer')[1],x:rounded(at[0]-outline.origin[0]),y:rounded(at[1]-outline.origin[1]),rotation:-(at[2]??0),width:rounded(width),height:rounded(height)};
}
function controls(pins,prefix) {
  return pins.map((pin,index)=>{
    const matches=footprints.filter(fp=>property(fp,'Reference')?.startsWith(prefix)&&node(fp,'layer')?.[1]==='F.Cu'&&nodes(fp,'pad').some(pad=>netOf(pad)===pin));
    if(matches.length!==1)throw Error(`Expected one front ${prefix} footprint on net ${pin}; got ${matches.length}`);
    return {...footprintData(matches[0]),index,net:pin};
  });
}
const buttons=controls(buttonsPins,'SW'),leds=controls(ledPins,'D');
const calibrationPath=new URL('vendor/greybadge26-display-calibration.json',root);
const calibrationSource=await readFile(calibrationPath,'utf8'),calibration=JSON.parse(calibrationSource);
const registration=photoRegistration(buttons.map(button=>({board:[button.x,button.y],photo:calibration.switchCenters[button.reference]})));
if(registration.error>2)throw Error(`Photo registration error too large: ${registration.error} pixels`);
const photoCenter=registration.unproject(calibration.displayCenter);
const contour=circleThroughPoints(calibration.faceContourPointsMm);
const center=[contour.x,contour.y],diameter=2*contour.r;
const axis=calibration.displayHorizontalAxis.map(registration.unproject);
const display={alignment:calibration.placement,x:rounded(center[0]),y:rounded(center[1]),diameter:rounded(diameter),activeDiameter:rounded(diameter*calibration.activeDiameterRatio),rotation:rounded(Math.atan2(axis[1][1]-axis[0][1],axis[1][0]-axis[0][0])*180/Math.PI),photoCenter:photoCenter.map(rounded),registrationErrorPixels:rounded(registration.error)};
const pads=[];
for(const fp of footprints)for(const pad of nodes(fp,'pad')) {
  const layers=node(pad,'layers')?.slice(1)??[];
  if(!layers.some(layer=>['F.Cu','*.Cu'].includes(layer))||!layers.some(layer=>['F.Mask','*.Mask'].includes(layer)))continue;
  const fpAt=numbers(fp,'at'),at=numbers(pad,'at'),p=pointTransform(at,fpAt),size=numbers(pad,'size'),drill=node(pad,'drill');
  const drillSize=drill?.slice(1).filter(value=>Number.isFinite(Number(value))).map(Number)??[];
  pads.push({x:rounded(p[0]-outline.origin[0]),y:rounded(p[1]-outline.origin[1]),width:size[0],height:size[1],rotation:-(at[2]??fpAt[2]??0),shape:pad[3],drill:drillSize});
}
const workspace=await mkdtemp(path.join(tmpdir(),'greymecha-board-'));
let silk;
try {
  const exported=path.join(workspace,'front.svg');
  execFileSync(cli,['pcb','export','svg','--layers','F.SilkS','--mode-single','--page-size-mode','2','--exclude-drawing-sheet','--output',exported,path.resolve(pcbPath)],{stdio:'pipe'});
  const svg=await readFile(exported,'utf8');
  silk=svg.slice(svg.indexOf('>',svg.indexOf('<svg'))+1,svg.lastIndexOf('</svg>'))
    .replace(/<title>[\s\S]*?<\/title>/g,'').replace(/<desc>[\s\S]*?<\/desc>/g,'').replace(/#[0-9a-f]{6}/gi,'#e8e8e4')
    .replace(/\r\n/g,'\n').replace(/[ \t]+$/gm,'');
} finally {
  if(path.dirname(workspace)!==path.resolve(tmpdir())||!path.basename(workspace).startsWith('greymecha-board-'))throw Error('Unexpected temporary export directory');
  await rm(workspace,{recursive:true,force:true});
}
const padSVG=pads.map(p=>{
  const round=p.shape==='circle',radius=p.shape==='roundrect'?Math.min(p.width,p.height)*.2:0;
  const body=round?`<ellipse rx="${p.width/2}" ry="${p.height/2}"/>`:`<rect x="${-p.width/2}" y="${-p.height/2}" width="${p.width}" height="${p.height}" rx="${radius}"/>`;
  const hole=p.drill.length?`<ellipse rx="${p.drill[0]/2}" ry="${(p.drill[1]??p.drill[0])/2}" fill="#101820" stroke="#655331" stroke-width="0.08"/>`:'';
  return `<g transform="translate(${p.x} ${p.y}) rotate(${p.rotation})" fill="#ba9d61">${body}${hole}</g>`;
}).join('\n');
const front=`<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 ${outline.width} ${outline.height}"><title>GreyMecha Army v2 front PCB, exported from KiCad</title><defs><clipPath id="board"><path d="${outline.path}" fill-rule="evenodd" clip-rule="evenodd"/></clipPath></defs><path d="${outline.path}" fill="#191d20" fill-rule="evenodd" stroke="#3b4041" stroke-width="0.16"/><g clip-path="url(#board)">${padSVG}<g>${silk}</g></g></svg>\n`;
let revision;try{revision=execFileSync('git',['-c','safe.directory=*','-C',path.dirname(path.resolve(pcbPath)),'rev-parse','HEAD'],{encoding:'utf8'}).trim();}catch{revision='unknown';}
const sha=data=>createHash('sha256').update(data).digest('hex');
const metadata={source:{project:'greybadge26',path:'greymechaarmy_v2/hardware/greybadge_pcb/greybadge_pcb.kicad_pcb',revision,sha256:sha(source),kiCad:execFileSync(cli,['version'],{encoding:'utf8'}).trim(),artwork:'Shuqing; PCB: hackin7, itsme-zeix, sayo',calibrationSha256:sha(calibrationSource),frontSvgSha256:sha(front)},outline,buttons,leds,display,pads};
await mkdir(destination,{recursive:true});
await writeFile(new URL('front.svg',destination),front);
await writeFile(new URL('src/lib/simulator/boardLayout.json',root),JSON.stringify(metadata,null,2)+'\n');
console.log(`Exported ${outline.width} x ${outline.height} mm board; ${buttons.length} buttons, ${leds.length} LEDs, ${pads.length} visible pads. Photo registration error ${display.registrationErrorPixels}px.`);
console.log(JSON.stringify({buttons,leds,display},null,2));
