"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [sent, setSent] = useState(false);
  const [error, setError] = useState<string | null>(null);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    const supabase = createClient();
    const { error } = await supabase.auth.signInWithOtp({
      email,
      options: { emailRedirectTo: `${location.origin}/auth/callback` },
    });
    if (error) setError(error.message);
    else setSent(true);
  }

  return (
    <main style={{ maxWidth: 420, margin: "4rem auto", padding: "0 1rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Тендер-радар</h1>
      <p>Вход по ссылке на почту (magic link).</p>
      {sent ? (
        <p>Письмо отправлено на <b>{email}</b>. Откройте ссылку из письма.</p>
      ) : (
        <form onSubmit={handleSubmit}>
          <input
            type="email"
            required
            placeholder="you@example.com"
            value={email}
            onChange={(e) => setEmail(e.target.value)}
            style={{ width: "100%", padding: 8, marginBottom: 8 }}
          />
          <button type="submit" style={{ padding: "8px 16px" }}>
            Получить ссылку
          </button>
          {error && <p style={{ color: "crimson" }}>{error}</p>}
        </form>
      )}
    </main>
  );
}
