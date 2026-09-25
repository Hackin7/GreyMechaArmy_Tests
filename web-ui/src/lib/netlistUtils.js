// netlistsvg's Yosys schema only accepts input and output directions. Represent
// each bidirectional port twice in a diagram so both signal directions remain
// visible without mutating the build artifact itself.
export function normalizeForNetlistSvg(source) {
  const design = structuredClone(source);

  for (const module of Object.values(design.modules ?? {})) {
    if (module.attributes && Object.hasOwn(module.attributes, 'top')) {
      const value = module.attributes.top;
      module.attributes.top = value === 0 || value === '0' || /^0+$/.test(String(value)) ? 0 : 1;
    }

    for (const [name, port] of Object.entries(module.ports ?? {})) {
      if (port.direction !== 'inout') continue;
      port.direction = 'input';
      module.ports[`${name}__netlistsvg_out`] = {
        ...structuredClone(port),
        direction: 'output'
      };
    }

    for (const cell of Object.values(module.cells ?? {})) {
      for (const [name, direction] of Object.entries(cell.port_directions ?? {})) {
        if (direction !== 'inout') continue;
        cell.port_directions[name] = 'input';
        const outputName = `${name}__netlistsvg_out`;
        cell.port_directions[outputName] = 'output';
        if (cell.connections?.[name]) {
          cell.connections[outputName] = [...cell.connections[name]];
        }
      }
    }
  }

  return design;
}
