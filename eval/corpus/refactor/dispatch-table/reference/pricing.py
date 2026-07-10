def _standard(qty):
    return qty * 10


def _bulk(qty):
    return qty * 7 if qty >= 100 else qty * 9


def _vip(qty):
    return qty * 8 - 5


RULES = {
    "standard": _standard,
    "bulk": _bulk,
    "vip": _vip,
}


def price(kind, qty):
    try:
        rule = RULES[kind]
    except KeyError:
        raise ValueError(f"unknown kind: {kind}")
    return rule(qty)
