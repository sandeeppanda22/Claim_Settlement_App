/// App-wide configuration. Backend base URL is the only thing that varies
/// per environment (dev/staging/prod) for v1 — no per-platform branching
/// needed since Flutter talks to the same JSON API everywhere.
/// See docs/ARCHITECTURE.md §1/§2.
class ApiConfig {
  ApiConfig._();

  /// Overridden at build time via --dart-define=API_BASE_URL=...
  /// Defaults to local FastAPI dev server.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:8000',
  );
}
