class KVStore:
    def __init__(self):
        # key -> (value, expires_at | None)
        self._store = {}

    def set(self, key, value, now, ttl=None):
        expires_at = None if ttl is None else float(now) + float(ttl)
        self._store[key] = (value, expires_at)

    def _is_live(self, entry, now):
        _, expires_at = entry
        return expires_at is None or float(now) < expires_at

    def get(self, key, now):
        entry = self._store.get(key)
        if entry is None:
            return None
        if not self._is_live(entry, now):
            del self._store[key]
            return None
        return entry[0]

    def delete(self, key):
        return self._store.pop(key, None) is not None

    def size(self, now):
        return sum(1 for entry in self._store.values() if self._is_live(entry, now))
