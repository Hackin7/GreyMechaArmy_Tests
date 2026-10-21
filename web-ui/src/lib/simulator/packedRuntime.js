import { HDLModuleJS } from '../../../vendor/8bitworkshop/hdl/hdlruntime.ts';

const width = expression => expression?.dtype?.left === undefined ? 0 : Math.abs(expression.dtype.left - expression.dtype.right) + 1;
const wide = expression => width(expression) > 32 && width(expression) <= 64;
const operators = { add: '+', sub: '-', mul: '*', div: '/', moddiv: '%', and: '&', or: '|', xor: '^', shiftl: '<<', shiftr: '>>', shiftrs: '>>',
  eq: '===', neq: '!==', lt: '<', lte: '<=', gt: '>', gte: '>=' };
const assignments = new Set(['contassign', 'assign', 'assignpre', 'assigndly', 'assignpost']);

// The upstream JS emitter prints 64-bit constants as Number literals and uses
// 32-bit JS bitwise operators. Keep scalar 33–64-bit values as BigInt instead.
// Wide word arrays (>64 bits) retain the backend's existing representation.
export class PackedRuntime extends HDLModuleJS {
  expr2js(expression, options) {
    if (!expression) return super.expr2js(expression, options);
    const e = expression, size = width(e);
    if (wide(e) && (typeof e.bigvalue === 'bigint' || typeof e.cvalue === 'number')) {
      return `${e.bigvalue ?? BigInt(e.cvalue)}n`;
    }
    const leftWide = wide(e.left), rightWide = wide(e.right);
    if (assignments.has(e.op)) {
      let value = this.expr2js(e.left);
      if (wide(e.right)) value = `BigInt.asUintN(${width(e.right)}, BigInt(${value}))`;
      else if (leftWide && width(e.right)) value = `Number(BigInt.asUintN(${width(e.right)}, BigInt(${value})))`;
      return `${this.expr2js(e.right, { store: true })} = ${value}`;
    }
    if (e.op === 'changedet' && (leftWide || rightWide)) {
      const left = this.expr2js(e.left), right = this.expr2js(e.right);
      return `$$req |= Number(BigInt(${left}) !== BigInt(${right})); ${right} = ${left}`;
    }
    if (e.op === 'ccast' && (wide(e) || leftWide)) {
      const value = `BigInt.asUintN(${size}, BigInt(${this.expr2js(e.left)}))`;
      return wide(e) ? value : `Number(${value})`;
    }
    if (operators[e.op] && (wide(e) || leftWide || rightWide)) {
      const operation = `(BigInt(${this.expr2js(e.left)}) ${operators[e.op]} BigInt(${this.expr2js(e.right)}))`;
      if (['eq', 'neq', 'lt', 'lte', 'gt', 'gte'].includes(e.op)) return options?.cond ? operation : `Number(${operation})`;
      const value = `BigInt.asUintN(${size || Math.max(width(e.left), width(e.right))}, ${operation})`;
      return wide(e) ? value : `Number(${value})`;
    }
    if (wide(e) && (e.op === 'not' || e.op === 'negate')) return `BigInt.asUintN(${size}, ${e.op === 'not' ? '~' : '-'}BigInt(${this.expr2js(e.left)}))`;
    return super.expr2js(e, options);
  }
}
