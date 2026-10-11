MAGIC = 0x47
VERSION = 1

OP_RESET = 0x01
OP_CONFIG = 0x02
OP_RUN = 0x03
OP_ROM_WRITE = 0x10
OP_CACHE_FILL = 0x11
OP_STATUS = 0x20


def crc16_ccitt(data, initial=0xFFFF):
    crc = initial
    for value in bytearray(data):
        crc ^= value << 8
        for _ in range(8):
            if crc & 0x8000:
                crc = ((crc << 1) ^ 0x1021) & 0xFFFF
            else:
                crc = (crc << 1) & 0xFFFF
    return crc


def encode_frame(opcode, sequence, address=0, payload=b""):
    payload = bytes(payload)
    if len(payload) > 256:
        raise ValueError("payload exceeds FPGA packet buffer")
    head = bytes(bytearray((MAGIC, VERSION, opcode & 0xFF, sequence & 0xFF)))
    head += bytes(bytearray((
        address & 0xFF, (address >> 8) & 0xFF,
        (address >> 16) & 0xFF, (address >> 24) & 0xFF,
        len(payload) & 0xFF, (len(payload) >> 8) & 0xFF)))
    body = head + payload
    crc = crc16_ccitt(body)
    return body + bytes(bytearray((crc & 0xFF, crc >> 8)))


def decode_frame(frame):
    frame = bytes(frame)
    if len(frame) < 12 or frame[0] != MAGIC or frame[1] != VERSION:
        raise ValueError("bad frame header")
    length = frame[8] | (frame[9] << 8)
    if len(frame) != 12 + length:
        raise ValueError("bad frame length")
    expected = frame[-2] | (frame[-1] << 8)
    if crc16_ccitt(frame[:-2]) != expected:
        raise ValueError("bad frame CRC")
    address = frame[4] | (frame[5] << 8) | (frame[6] << 16) | (frame[7] << 24)
    return {
        "opcode": frame[2], "sequence": frame[3], "address": address,
        "payload": frame[10:-2]
    }


def decode_status(data):
    data = bytes(data)
    if len(data) != 4:
        raise ValueError("status response must contain four bytes")
    return {
        "cache_miss": bool(data[0] & 0x80),
        "error": data[0] & 0x0F,
        "address": data[1] | (data[2] << 8) | ((data[3] & 0x7F) << 16),
    }
