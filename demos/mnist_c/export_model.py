"""Export the user's Vivado COE model and independent integer test vectors."""
import argparse
import hashlib
import re
from pathlib import Path


def read_coe(path, count, binary=False):
    text = path.read_text()
    radix_match = re.search(r'memory_initialization_radix\s*=\s*(\d+)\s*;', text, re.I)
    vector_match = re.search(r'memory_initialization_vector\s*=\s*([^;]*);', text, re.I)
    if not radix_match or not vector_match:
        raise ValueError('Missing COE radix/vector: {}'.format(path))
    radix = int(radix_match.group(1))
    if radix not in (2, 10, 16):
        raise ValueError('Unsupported COE radix')
    words = [int(token.strip(), radix) for token in vector_match.group(1).split(',')
             if token.strip()]
    if len(words) != count or any(v < 0 or v > (1 if binary else 65535) for v in words):
        raise ValueError('Invalid values or count in {}'.format(path))
    return words if binary else [v - 65536 if v >= 32768 else v for v in words]


def array(name, ctype, values):
    lines = [', '.join(str(v) for v in values[i:i + 12])
             for i in range(0, len(values), 12)]
    return 'static const {} {}[{}] = {{\n    {}\n}};\n'.format(
        ctype, name, len(values), ',\n    '.join(lines))


def reference(image, weights):
    hidden = [max(0, sum(image[j] * weights[i * 784 + j] for j in range(784))
                  + 4 * weights[50816 + i]) for i in range(64)]
    scores = [sum(hidden[j] * weights[50176 + i * 64 + j] for j in range(64))
              + weights[50880 + i] for i in range(10)]
    return hidden + scores, max(range(10), key=lambda i: scores[i])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--weights', required=True, type=Path)
    parser.add_argument('--image', required=True, type=Path)
    parser.add_argument('--out', type=Path, default=Path('build/generated'))
    args = parser.parse_args()
    weights = read_coe(args.weights, 50890)
    cases = [('provided_00', read_coe(args.image, 784, binary=True)),
             ('blank', [0] * 784), ('full', [1] * 784),
             ('stroke', [int(i % 29 == 0 or i % 28 == 14) for i in range(784)]),
             ('mixed', [int((i * 73 + 19) % 101 < 37) for i in range(784)])]
    args.out.mkdir(parents=True, exist_ok=True)
    header = '#ifndef NN_MODEL_DATA_H\n#define NN_MODEL_DATA_H\n#include <stdint.h>\n'
    header += '#define NN_MODEL_SHA256 "{}"\n'.format(hashlib.sha256(args.weights.read_bytes()).hexdigest())
    header += array('model_weights', 'int16_t', weights)
    header += '#endif\n'
    (args.out / 'model_data.h').write_text(header)
    tests = '#ifndef NN_TEST_DATA_H\n#define NN_TEST_DATA_H\n#include <stdint.h>\n'
    tests += '#define NN_TEST_CASES {}\n'.format(len(cases))
    for i, (name, image) in enumerate(cases):
        values, digit = reference(image, weights)
        tests += array('image_{}'.format(i), 'uint8_t', image)
        # INT64_C keeps large oracle values portable to 32-bit targets.
        tests += array('expected_{}'.format(i), 'int64_t',
                       ['INT64_C({})'.format(v) for v in values])
        tests += '#define DIGIT_{} {}\n'.format(i, digit)
    tests += 'static const uint8_t *const test_images[] = {' + ', '.join(
        'image_{}'.format(i) for i in range(len(cases))) + '};\n'
    tests += 'static const int64_t *const test_expected[] = {' + ', '.join(
        'expected_{}'.format(i) for i in range(len(cases))) + '};\n'
    tests += 'static const unsigned test_digits[] = {' + ', '.join(
        'DIGIT_{}'.format(i) for i in range(len(cases))) + '};\n'
    tests += 'static const char *const test_names[] = {' + ', '.join(
        '"{}"'.format(name) for name, _ in cases) + '};\n#endif\n'
    (args.out / 'test_data.h').write_text(tests)
    print('Exported {} constants, {} oracle cases; SHA256={}'.format(
        len(weights), len(cases), hashlib.sha256(args.weights.read_bytes()).hexdigest()))


if __name__ == '__main__':
    main()
