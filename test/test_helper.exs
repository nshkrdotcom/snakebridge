ExUnit.start()

# Exclude integration, external, and slow tests by default
ExUnit.configure(exclude: [:integration, :external, :slow])

# Define Mox mocks for protocol-based testing
Mox.defmock(SnakeBridge.Discovery.IntrospectorMock,
  for: SnakeBridge.Discovery.IntrospectorBehaviour
)
