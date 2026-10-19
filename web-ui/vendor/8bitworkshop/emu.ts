// GreyMecha adapter: the HDL runtime needs only this error type from the IDE.
export class EmuHalt extends Error {
  $loc: unknown;
  constructor(message: string, location?: unknown) {
    super(message);
    this.$loc = location;
  }
}
