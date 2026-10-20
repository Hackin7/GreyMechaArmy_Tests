import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {parsePCB,boardOutline,photoRegistration,pointTransform,circleThroughPoints} from './pcb-geometry.mjs';
const root=new URL('../',import.meta.url);
const layout=JSON.parse(await readFile(new URL('src/lib/simulator/boardLayout.json',root),'utf8'));
const calibration=await readFile(new URL('vendor/greybadge26-display-calibration.json',root),'utf8');
const svg=await readFile(new URL('public/simulator/board/front.svg',root),'utf8');
const sha=value=>createHash('sha256').update(value).digest('hex');
assert.equal(sha(svg),layout.source.frontSvgSha256,'PCB front export changed without refreshing its manifest');
assert.equal(sha(calibration),layout.source.calibrationSha256,'Display calibration changed without refreshing layout');
assert.deepEqual(layout.buttons.map(p=>p.reference),['SW4','SW1','SW5','SW7','SW3','SW2','SW6']);
assert.deepEqual(layout.buttons.map(p=>p.net),['B4','A5','B5','A6','B6','D12','C12']);
assert.deepEqual(layout.leds.map(p=>p.reference),['D1','D3','D5','D8','D2','D4','D6','D7']);
assert.deepEqual(layout.leds.map(p=>p.net),['C3','D3','C4','D4','C5','D5','C6','D6']);
assert.equal(layout.outline.width,75);assert.equal(layout.outline.height,99);
assert.equal(layout.outline.loops,2,'Expected outer edge and lanyard slot');
for(const parts of [layout.buttons,layout.leds])for(const [i,p] of parts.entries()) {
  assert.equal(p.index,i);assert.equal(p.layer,'F.Cu');
  assert.ok(p.x>0&&p.x<75&&p.y>0&&p.y<99,`${p.reference} outside board`);
}
// Test joins, rounded corners and coordinate rotation independently of the real board.
const sample=parsePCB(`(kicad_pcb (gr_line(start 1 0)(end 9 0)(layer "Edge.Cuts"))
 (gr_arc(start 9 0)(mid 9.707106781 0.292893219)(end 10 1)(layer "Edge.Cuts"))
 (gr_line(start 10 1)(end 10 5)(layer "Edge.Cuts"))
 (gr_line(start 0 5)(end 10 5)(layer "Edge.Cuts"))
 (gr_line(start 0 5)(end 0 1)(layer "Edge.Cuts"))
 (gr_arc(start 0 1)(mid 0.292893219 0.292893219)(end 1 0)(layer "Edge.Cuts")))`);
const shape=boardOutline(sample);
assert.equal(shape.width,10);assert.equal(shape.height,5);assert.equal(shape.loops,1);assert.match(shape.path,/A 1 1/);
assert.throws(()=>boardOutline(parsePCB('(kicad_pcb (gr_line(start 0 0)(end 1 1)(layer "Edge.Cuts")))')),/Open/);
assert.ok(Math.abs(pointTransform([1,0],[3,4,90])[1]-3)<1e-9);
const photo=JSON.parse(calibration),registration=photoRegistration(layout.buttons.map(p=>({board:[p.x,p.y],photo:photo.switchCenters[p.reference]})));
assert.ok(registration.error<1,'Photo fiducials drifted');
const center=registration.unproject(photo.displayCenter);
assert.ok(Math.hypot(center[0]-layout.display.photoCenter[0],center[1]-layout.display.photoCenter[1])<.00001);
assert.equal(layout.display.alignment,'art-face-contour');
const contour=circleThroughPoints(photo.faceContourPointsMm);
assert.ok(Math.hypot(contour.x-layout.display.x,contour.y-layout.display.y)<.00001);
assert.ok(Math.abs(contour.r*2-layout.display.diameter)<.00001);
assert.ok(layout.display.activeDiameter>37,'Display should fill the enlarged face opening');
assert.ok(layout.display.activeDiameter<layout.display.diameter);
assert.ok(layout.display.rotation>-20&&layout.display.rotation<-5);
assert.ok(layout.pads.length>100);
assert.match(svg,/<clipPath/);assert.match(svg,/fill-rule="evenodd"/);
assert.doesNotMatch(svg,/<script|<image|https?:\/\/(?!www.w3.org)/);
console.log('PCB outline, exported artwork hash, net-to-control mapping, geometry, and photo registration passed.');
