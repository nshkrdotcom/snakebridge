"""Local module for streaming example."""

import time


def generate(prompt, stream=False, count=3, delay=0.01):
    """Generate either a full response or a stream of chunks."""
    if stream:
        def _chunks():
            for i in range(count):
                if delay:
                    time.sleep(delay)
                yield {"chunk": f"{prompt}-{i + 1}", "index": i + 1}

        return _chunks()

    return f"{prompt}-{count}"
