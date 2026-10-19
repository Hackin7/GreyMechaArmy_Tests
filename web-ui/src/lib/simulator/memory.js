export function loadMemory(files, filename, memory, start = 0, end = 0xffffffff, hex = true, width = 32) {
  let name;
  if (typeof filename === 'string') name = filename;
  else {
    const words = typeof filename === 'number' ? [filename] : Array.from(filename);
    const bytes = [];
    for (const word of words) for (let n=0;n<4;n++) bytes.push((word >>> (n*8)) & 255);
    name = String.fromCharCode(...bytes.filter(value=>value!==0).reverse());
  }
  if (typeof files[name] !== 'string') throw new Error(`Missing simulation memory file ${name}.`);
  if (!memory) throw new Error(`No destination array for ${name}.`);
  const last = end === 0xffffffff ? memory.length - 1 : end;
  const direction = start <= last ? 1 : -1;
  let address = start;
  const tokens = files[name].replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g,' ').trim().split(/\s+/).filter(Boolean);
  for (let token of tokens) {
    token = token.replace(/_/g,'');
    if (token.startsWith('@')) {
      if (!/^@[\da-f]+$/i.test(token)) throw new Error(`Invalid memory address ${token} in ${name}.`);
      address = parseInt(token.slice(1),16); continue;
    }
    if (!(hex ? /^[\da-fxz?]+$/i : /^[01xz?]+$/i).test(token)) throw new Error(`Invalid memory word ${token} in ${name}.`);
    if (address < 0 || address >= memory.length || (direction>0 ? address>last : address<last)) throw new Error(`Memory file ${name} exceeds the requested array range.`);
    token=token.replace(/[xz?]/gi,'0');
    const value = BigInt((hex?'0x':'0b')+token) & ((1n<<BigInt(width))-1n);
    memory[address] = typeof memory[address] === 'bigint' ? value : Number(value);
    address+=direction;
  }
}
