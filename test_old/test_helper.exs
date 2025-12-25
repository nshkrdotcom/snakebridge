ExUnit.start()

# Exclude integration, external, slow, and real_python tests by default
# Run with: mix test --include real_python
# Run with: mix test --include integration
# Run with: mix test --include gpu
ExUnit.configure(exclude: [:integration, :external, :slow, :real_python, :gpu])

# Define Mox mocks for protocol-based testing
Mox.defmock(SnakeBridge.Discovery.IntrospectorMock,
  for: SnakeBridge.Discovery.IntrospectorBehaviour
)
