"""Check accumulator bounds, signed scores, ties, and random binary inputs."""
import ctypes
import random
from pathlib import Path
from export_model import reference


class Result(ctypes.Structure):
    _fields_ = [('hidden', ctypes.c_int64 * 64),
                ('scores', ctypes.c_int64 * 10), ('digit', ctypes.c_uint)]


def main():
    library = ctypes.CDLL(str((Path(__file__).parent / 'build/neural_net_test.dll').resolve()))
    functions = []
    for name in ('nn_reference', 'nn_binary32', 'nn_sparse32'):
        fn = getattr(library, name)
        fn.argtypes = [ctypes.POINTER(ctypes.c_uint8), ctypes.POINTER(ctypes.c_int16),
                       ctypes.POINTER(Result)]
        fn.restype = None
        functions.append((name, fn))
    rng = random.Random(2026)
    cases = [('maximum', [1] * 784, [32767] * 50890),
             ('minimum', [1] * 784, [-32768] * 50890),
             ('negative_scores', [1] * 784,
              [32767] * 50176 + [-32768] * (50890 - 50176))]
    for i in range(8):
        cases.append(('random_{}'.format(i), [rng.randrange(2) for _ in range(784)],
                      [rng.randrange(-32768, 32768) for _ in range(50890)]))
    for label, image, weights in cases:
        expected, digit = reference(image, weights)
        image_c = (ctypes.c_uint8 * 784)(*image)
        weights_c = (ctypes.c_int16 * 50890)(*weights)
        for name, infer in functions:
            result = Result()
            infer(image_c, weights_c, ctypes.byref(result))
            got = list(result.hidden) + list(result.scores)
            if got != expected or result.digit != digit:
                raise AssertionError('{} failed {}'.format(name, label))
    print('PASS arithmetic: {} cases x {} variants x 74 values, including ties and signed bounds'.format(
        len(cases), len(functions)))


if __name__ == '__main__':
    main()
