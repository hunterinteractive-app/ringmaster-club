class SupabaseConfig {
  // Local dev defaults (safe for public apps — this is anon key)
  static const String url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://ksptuduzuzsfhgqjghwx.supabase.co',
  );

  static const String anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImtzcHR1ZHV6dXpzZmhncWpnaHd4Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODA4NTM3OTMsImV4cCI6MjA5NjQyOTc5M30.jR_bmvwxZbEx9Q_WcyGrA2PMN9YzmveAnNZjUMJ2qkw',
  );

  static void validate() {
    assert(
      url.isNotEmpty && anonKey.isNotEmpty,
      'Missing Supabase config',
    );
  }
}