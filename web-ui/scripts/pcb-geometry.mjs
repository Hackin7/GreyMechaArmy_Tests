// Read-only KiCad S-expression inspection. No KiCad project is rewritten.
export function parsePCB(text) {
  const tokens = text.match(/"(?:\\.|[^"\\])*"|[()]|[^\s()]+/g) ?? [];
  const root = [], stack = [root];
  for (const token of tokens) {
    if (token === '(') { const list = []; stack.at(-1).push(list); stack.push(list); }
    else if (token === ')') { if (stack.length === 1) throw Error('Unbalanced PCB expression'); stack.pop(); }
    else stack.at(-1).push(token.startsWith('"') ? JSON.parse(token) : token);
  }
  if (stack.length !== 1 || root[0]?.[0] !== 'kicad_pcb') throw Error('Invalid KiCad PCB');
  return root[0];
}
export const nodes = (node, name) => node.filter(item => Array.isArray(item) && item[0] === name);
export const node = (parent, name) => nodes(parent, name)[0];
export const numbers = (parent, name) => (node(parent, name)?.slice(1) ?? []).map(Number);
export const property = (parent, name) => nodes(parent, 'property').find(item => item[1] === name)?.[2];
export const rounded = value => Number(value.toFixed(6));
export function pointTransform([x, y], [cx, cy, angle = 0]) {
  const a = -angle * Math.PI / 180;
  return [cx + x * Math.cos(a) - y * Math.sin(a), cy + x * Math.sin(a) + y * Math.cos(a)];
}
function arcGeometry(start, mid, end) {
  const [ax, ay] = start, [bx, by] = mid, [cx, cy] = end;
  const d = 2 * (ax * (by-cy) + bx * (cy-ay) + cx * (ay-by));
  if (Math.abs(d) < 1e-12) throw Error('Degenerate Edge.Cuts arc');
  const aa = ax*ax+ay*ay, bb = bx*bx+by*by, cc = cx*cx+cy*cy;
  const x = (aa*(by-cy)+bb*(cy-ay)+cc*(ay-by))/d;
  const y = (aa*(cx-bx)+bb*(ax-cx)+cc*(bx-ax))/d;
  const r = Math.hypot(ax-x,ay-y), tau = 2*Math.PI;
  const angles = [start,mid,end].map(([px,py]) => Math.atan2(py-y,px-x));
  const positive = angle => (angle+tau)%tau;
  const sweep = positive(angles[1]-angles[0]) < positive(angles[2]-angles[0]) ? 1 : 0;
  const delta = sweep ? positive(angles[2]-angles[0]) : -positive(angles[0]-angles[2]);
  return { x,y,r,sweep,large:Math.abs(delta)>Math.PI?1:0,points:Array.from({length:101},(_,i)=>[x+r*Math.cos(angles[0]+delta*i/100),y+r*Math.sin(angles[0]+delta*i/100)]) };
}
export function circleThroughPoints(points) {
  if(points.length!==3)throw Error('A circle needs three contour landmarks');
  const {x,y,r}=arcGeometry(...points);return {x,y,r};
}
export function boardOutline(board) {
  const segments = board.filter(item => Array.isArray(item) && ['gr_line','gr_arc'].includes(item[0]) && node(item,'layer')?.[1] === 'Edge.Cuts')
    .map(item => ({ start:numbers(item,'start'),end:numbers(item,'end'),mid:item[0]==='gr_arc'?numbers(item,'mid'):undefined }));
  if (!segments.length) throw Error('PCB has no supported Edge.Cuts outline');
  const points = segments.flatMap(s=>s.mid?arcGeometry(s.start,s.mid,s.end).points:[s.start,s.end]);
  const origin = [Math.min(...points.map(p=>p[0])),Math.min(...points.map(p=>p[1]))];
  const width = Math.max(...points.map(p=>p[0]))-origin[0], height = Math.max(...points.map(p=>p[1]))-origin[1];
  const local = p=>p.map((v,i)=>rounded(v-origin[i])).join(' ');
  const paths = [];
  while (segments.length) {
    const first = segments.shift(), chain = [first]; let end = first.end;
    while (Math.hypot(end[0]-first.start[0],end[1]-first.start[1])>.001) {
      const index = segments.findIndex(s=>[s.start,s.end].some(p=>Math.hypot(p[0]-end[0],p[1]-end[1])<.001));
      if(index<0) throw Error('Open Edge.Cuts chain');
      const s=segments.splice(index,1)[0];
      if(Math.hypot(s.end[0]-end[0],s.end[1]-end[1])<.001) [s.start,s.end]=[s.end,s.start];
      chain.push(s);end=s.end;
    }
    paths.push(`M ${local(first.start)} `+chain.map(s=>{
      if(!s.mid) return `L ${local(s.end)}`;
      const a=arcGeometry(s.start,s.mid,s.end);
      return `A ${rounded(a.r)} ${rounded(a.r)} 0 ${a.large} ${a.sweep} ${local(s.end)}`;
    }).join(' ')+' Z');
  }
  return {origin:origin.map(rounded),width:rounded(width),height:rounded(height),path:paths.join(' '),loops:paths.length};
}
// Least-squares projective registration, using all seven switch centres.
export function photoRegistration(fiducials) {
  const rows=[],values=[];
  for(const {board:[x,y],photo:[u,v]} of fiducials) {
    rows.push([x,y,1,0,0,0,-u*x,-u*y],[0,0,0,x,y,1,-v*x,-v*y]);values.push(u,v);
  }
  const a=Array.from({length:8},(_,i)=>Array.from({length:9},(_,j)=>j===8?rows.reduce((s,row,k)=>s+row[i]*values[k],0):rows.reduce((s,row)=>s+row[i]*row[j],0)));
  for(let col=0;col<8;col++) {
    let pivot=col;for(let r=col+1;r<8;r++)if(Math.abs(a[r][col])>Math.abs(a[pivot][col]))pivot=r;
    [a[col],a[pivot]]=[a[pivot],a[col]];
    const divisor=a[col][col];if(Math.abs(divisor)<1e-10)throw Error('Invalid photo registration');
    for(let c=col;c<=8;c++)a[col][c]/=divisor;
    for(let r=0;r<8;r++)if(r!==col){const factor=a[r][col];for(let c=col;c<=8;c++)a[r][c]-=factor*a[col][c];}
  }
  const h=a.map(row=>row[8]);
  const project=([x,y])=>[(h[0]*x+h[1]*y+h[2])/(h[6]*x+h[7]*y+1),(h[3]*x+h[4]*y+h[5])/(h[6]*x+h[7]*y+1)];
  // Solve the two linear equations for a photo point's board position.
  const unproject=([u,v])=>{
    const a=h[0]-u*h[6],b=h[1]-u*h[7],c=u-h[2],d=h[3]-v*h[6],e=h[4]-v*h[7],f=v-h[5];
    return [(c*e-b*f)/(a*e-b*d),(a*f-c*d)/(a*e-b*d)];
  };
  return {project,unproject,error:Math.sqrt(fiducials.reduce((sum,f)=>sum+project(f.board).reduce((s,v,i)=>s+(v-f.photo[i])**2,0),0)/fiducials.length)};
}
