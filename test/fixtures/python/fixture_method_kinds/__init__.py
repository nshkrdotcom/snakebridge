class DescriptorDemo:
    def __init__(self, value=1):
        self.value = value

    def instance_value(self, suffix=""):
        return f"{self.value}{suffix}"

    @classmethod
    def from_value(cls, value, scale=2):
        return cls(value * scale)

    @staticmethod
    def add(left, right=1):
        return left + right

    @property
    def doubled(self):
        return self.value * 2
