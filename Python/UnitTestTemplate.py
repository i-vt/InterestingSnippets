'''
# Contents of add.py file

# Code to be tested
def add(a, b):
    return a + b
'''

import unittest

from my_module import add

class TestAddFunction(unittest.TestCase):
    def test_add_positive_numbers(self):
        result = add(2, 3)
        self.assertEqual(result, 5)

    def test_add_negative_numbers(self):
        result = add(-2, -3)
        self.assertEqual(result, -5)

    def test_add_mixed_numbers(self):
        result = add(2, -3)
        self.assertEqual(result, -1)

    def test_add_zero(self):
        result = add(5, 0)
        self.assertEqual(result, 5)

if __name__ == '__main__':
    unittest.main()

'''
Output:
....
----------------------------------------------------------------------
Ran 4 tests in 0.001s

OK
'''
