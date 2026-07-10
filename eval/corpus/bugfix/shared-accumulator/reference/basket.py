def add_items(new_items, basket=None):
    if basket is None:
        basket = []
    for item in new_items:
        basket.append(item)
    return basket
