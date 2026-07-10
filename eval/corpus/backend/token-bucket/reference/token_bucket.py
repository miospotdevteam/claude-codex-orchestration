class TokenBucket:
    """A continuous-refill token bucket with an injected clock."""

    def __init__(self, capacity, refill_per_sec, start=0.0):
        self.capacity = float(capacity)
        self.refill_per_sec = float(refill_per_sec)
        self.tokens = float(capacity)
        self.last = float(start)

    def allow(self, now, tokens=1):
        now = float(now)
        elapsed = now - self.last
        if elapsed > 0:
            self.tokens = min(
                self.capacity, self.tokens + elapsed * self.refill_per_sec
            )
            self.last = now
        if self.tokens >= tokens:
            self.tokens -= tokens
            return True
        return False
