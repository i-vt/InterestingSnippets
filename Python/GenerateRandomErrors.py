import random

def throw_random_exception():
    exceptions = [
        ValueError,
        TypeError,
        KeyError,
        IndexError,
        ZeroDivisionError,
        FileNotFoundError,
        PermissionError,
        RuntimeError,
        NotImplementedError,
        OverflowError,
        MemoryError,
        AttributeError,
        AssertionError,
        ImportError,
        NameError,
        StopIteration,
        TimeoutError,
        OSError,
        BrokenPipeError,
        UnicodeDecodeError,
        UnicodeEncodeError,
    ]

    exc = random.choice(exceptions)

    # Some exceptions require special arguments
    if exc is UnicodeDecodeError:
        raise exc("codec", b"\xff", 0, 1, "invalid start byte")
    elif exc is UnicodeEncodeError:
        raise exc("codec", "☃", 0, 1, "cannot encode character")

    raise exc(f"Randomly triggered {exc.__name__}")

# Example usage
if __name__ == "__main__":
    throw_random_exception()
