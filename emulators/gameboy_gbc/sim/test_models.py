import os
import sys
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "badge"))

from protocol import crc16_ccitt, decode_frame, decode_status, encode_frame, OP_ROM_WRITE


class ProtocolTests(unittest.TestCase):
    def test_standard_crc_vector(self):
        self.assertEqual(crc16_ccitt(b"123456789"), 0x29B1)

    def test_frame_round_trip_and_fault(self):
        frame = encode_frame(OP_ROM_WRITE, 19, 0x123456, bytes(range(256)))
        decoded = decode_frame(frame)
        self.assertEqual(decoded["sequence"], 19)
        self.assertEqual(decoded["address"], 0x123456)
        self.assertEqual(decoded["payload"], bytes(range(256)))
        bad = bytearray(frame); bad[22] ^= 0x01
        with self.assertRaises(ValueError):
            decode_frame(bad)

    def test_cache_miss_status(self):
        status = decode_status(bytes((0x80, 0x00, 0x34, 0x12)))
        self.assertTrue(status["cache_miss"])
        self.assertEqual(status["address"], 0x123400)


class ClockEnableTests(unittest.TestCase):
    def test_exact_reduced_period(self):
        phase = 0
        half = 0
        ce = ce_n = ce2 = 0
        for _ in range(62500):
            phase += 32768
            if phase >= 62500:
                phase -= 62500
                ce2 += 1
                if half: ce_n += 1
                else: ce += 1
                half ^= 1
        self.assertEqual((phase, ce2, ce, ce_n), (0, 32768, 16384, 16384))


class CacheModelTests(unittest.TestCase):
    def test_two_way_lru_replacement(self):
        tags = [[None, None] for _ in range(16)]
        lru = [0] * 16
        def access(address):
            line = address >> 8; index = line & 15; tag = line >> 4
            for way in range(2):
                if tags[index][way] == tag:
                    lru[index] = 1 - way
                    return True
            way = lru[index]; tags[index][way] = tag; lru[index] = 1 - way
            return False
        self.assertFalse(access(0x0000))
        self.assertFalse(access(0x1000))
        self.assertTrue(access(0x0000))
        self.assertFalse(access(0x2000))
        self.assertTrue(access(0x0000))
        self.assertFalse(access(0x1000))


class BootRomTests(unittest.TestCase):
    def test_generated_boot_rom_size(self):
        path = os.path.join(ROOT, "build", "generated", "cgb_boot.hex")
        with open(path, "r") as source:
            values = [line.strip() for line in source if line.strip()]
        self.assertEqual(len(values), 4096)
        self.assertTrue(all(len(value) == 2 for value in values))


if __name__ == "__main__":
    unittest.main()
