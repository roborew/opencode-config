# Deepening

Classify dependencies before deepening a module: in-process logic can be merged and tested directly; local-substitutable dependencies use a test stand-in; remote-owned and external dependencies use an injected port with production and in-memory/mock adapters.

Keep internal seams private. Replace shallow-module tests with behaviour tests through the deep module's interface. Tests should assert observable outcomes and survive internal refactors.
