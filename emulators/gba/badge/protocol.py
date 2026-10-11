"""GBA host wire format shared by CircuitPython and desktop tooling."""
import struct


def crc16(data):
    crc = 0xffff
    for value in data:
        crc ^= value << 8
        for _ in range(8):
            crc = ((crc << 1) ^ (0x1021 if crc & 0x8000 else 0)) & 0xffff
    return crc


def encode_frame(opcode, sequence, address=0, payload=b''):
    if len(payload) > 256:
        raise ValueError('Payload exceeds 256 bytes')
    data = struct.pack('<BBBBIH', 0x47, 1, opcode, sequence, address, len(payload)) + payload
    return data + struct.pack('<H', crc16(data))


def decode_status(data):
    if len(data) != 32 or data[:2] != b'G\x01':
        raise RuntimeError('Invalid GBA status frame: ' + repr(data))
    flags = data[3]
    return dict(sequence=data[2], busy=bool(flags & 1), run=bool(flags & 2),
                pause=bool(flags & 4), ram_ready=bool(flags & 8), ram_idle=bool(flags & 16),
                panel_ready=bool(flags & 32), ram_fault=bool(flags & 64), overflow=bool(flags & 128),
                pc=struct.unpack_from('<I', data, 4)[0],
                device_id=data[8] | data[9] << 8 | data[10] << 16,
                error=data[11], keys=data[12] | (data[13] & 3) << 8, physical=data[14],
                frames=struct.unpack_from('<I', data, 16)[0],
                flash_misses=struct.unpack_from('<I', data, 20)[0])
