"use client";

import { useEffect, useState, useCallback } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";
import type { RadarRow } from "@/types/db";

export default function RadarsPage() {
  const [radars, setRadars] = useState<RadarRow[]>([]);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    const supabase = createClient();
    const { data } = await supabase
      .from("radars")
      .select("*")
      .order("created_at", { ascending: false });
    setRadars((data ?? []) as RadarRow[]);
    setLoading(false);
  }, []);

  useEffect(() => {
    // Загрузка при монтировании: setState происходит асинхронно (после await),
    // каскадного ре-рендера нет. Realtime-обновление придёт в Фазе 6 (US-5).
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  async function toggle(r: RadarRow) {
    const supabase = createClient();
    await supabase.from("radars").update({ is_active: !r.is_active }).eq("id", r.id);
    void load();
  }

  async function remove(r: RadarRow) {
    if (!confirm(`Удалить радар «${r.name}»?`)) return;
    const supabase = createClient();
    await supabase.from("radars").delete().eq("id", r.id);
    void load();
  }

  async function logout() {
    const supabase = createClient();
    await supabase.auth.signOut();
    location.href = "/login";
  }

  return (
    <main style={{ maxWidth: 760, margin: "2rem auto", padding: "0 1rem", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>Мои радары</h1>
        <button onClick={logout} style={{ padding: "6px 12px" }}>Выйти</button>
      </div>
      <Link href="/radars/new"><button style={{ padding: "8px 16px", marginBottom: 16 }}>+ Новый радар</button></Link>

      {loading ? (
        <p>Загрузка…</p>
      ) : radars.length === 0 ? (
        <p>Радаров пока нет. Создайте первый.</p>
      ) : (
        <ul style={{ listStyle: "none", padding: 0 }}>
          {radars.map((r) => (
            <li key={r.id} style={{ border: "1px solid #ddd", borderRadius: 8, padding: 12, marginBottom: 10 }}>
              <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
                <div>
                  <b>{r.name}</b> {r.is_active ? "🟢" : "⚪️"}
                  <div style={{ color: "#666", fontSize: 14 }}>
                    регионы: {r.regions.join(", ")} · ОКПД2: {r.okpd_prefixes.join(", ") || "—"} · {r.law}-ФЗ
                  </div>
                </div>
                <div style={{ display: "flex", gap: 8 }}>
                  <Link href={`/radars/${r.id}`}><button>Изм.</button></Link>
                  <button onClick={() => toggle(r)}>{r.is_active ? "Выкл" : "Вкл"}</button>
                  <button onClick={() => remove(r)} style={{ color: "crimson" }}>Удал.</button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </main>
  );
}
