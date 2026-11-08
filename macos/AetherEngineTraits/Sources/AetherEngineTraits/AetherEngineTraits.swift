@_exported import AetherEngine

/// The optional engine components this build was compiled with.
public let enabledOptionalComponents = AetherEngine.OptionalComponent.allCases.filter(\.isBuiltIn)
