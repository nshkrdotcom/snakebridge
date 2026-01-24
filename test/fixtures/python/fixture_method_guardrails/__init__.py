class Base:
    pass


def _make_base_method(i: int):
    def method(self):
        return i

    method.__name__ = f"base_method_{i}"
    return method


for _i in range(20):
    setattr(Base, f"base_method_{_i}", _make_base_method(_i))


class Derived(Base):
    def derived_method(self):
        return "ok"

