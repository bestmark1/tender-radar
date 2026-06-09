"use client";

import { useCallback, useEffect, useState } from "react";
import Link from "next/link";
import { createClient } from "@/lib/supabase/client";

type MatchRow = {
  id: string;
  status: "new" | "interested" | "hidden";
  tenders: {
    title: string | null;
    customer: string | null;
    price: number | null;
    okpd: string | null;
    region: string | null;
    submission_deadline: string | null;
    eis_url: string | null;
  } | null;
  radars: { name: string | null } | null;
};

function daysLeft(deadline: string | null): number | null {
  if (!deadline) return null;
  return Math.ceil((new Date(deadline).getTime() - Date.now()) / 86400000);
}

function fmtPrice(p: number | null): string {
  return p != null ? Number(p).toLocaleString("ru-RU") + " ₽" : "—";
}

const card: React.CSSProperties = { border: "1px solid #ddd", borderRadius: 8, padding: 14, marginBottom: 12 };

export default function TendersPage() {
  const [rows, setRows] = useState<MatchRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [filter, setFilter] = useState<"active" | "interested" | "all">("active");

  const load = useCallback(async () => {
    const supabase = createClient();
    const { data } = await supabase
      .from("matches")
      .select(
        "id,status,tenders(title,customer,price,okpd,region,submission_deadline,eis_url),radars(name)",
      );
    const list = ((data ?? []) as unknown as MatchRow[]).sort((a, b) => {
      const da = a.tenders?.submission_deadline ?? "9999";
      const db = b.tenders?.submission_deadline ?? "9999";
      return da < db ? -1 : da > db ? 1 : 0;
    });
    setRows(list);
    setLoading(false);
  }, []);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect
    void load();
  }, [load]);

  async function setStatus(id: string, status: MatchRow["status"]) {
    const supabase = createClient();
    await supabase.from("matches").update({ status }).eq("id", id);
    void load();
  }

  const visible = rows.filter((r) => {
    if (filter === "all") return true;
    if (filter === "interested") return r.status === "interested";
    return r.status !== "hidden"; // active
  });

  return (
    <main style={{ maxWidth: 820, margin: "2rem auto", padding: "0 1rem", fontFamily: "system-ui, sans-serif" }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
        <h1>Найденные закупки</h1>
        <Link href="/radars"><button>Мои радары →</button></Link>
      </div>

      <div style={{ display: "flex", gap: 8, marginBottom: 16 }}>
        {(["active", "interested", "all"] as const).map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            style={{ padding: "6px 12px", fontWeight: filter === f ? 700 : 400 }}
          >
            {f === "active" ? "Актуальные" : f === "interested" ? "Интересные" : "Все"}
          </button>
        ))}
      </div>

      {loading ? (
        <p>Загрузка…</p>
      ) : visible.length === 0 ? (
        <p>Совпадений пока нет. Закупки появятся после прогона фильтрации (n8n WF2).</p>
      ) : (
        visible.map((r) => {
          const t = r.tenders;
          const dl = daysLeft(t?.submission_deadline ?? null);
          const urgent = dl != null && dl <= 2;
          return (
            <div key={r.id} style={card}>
              <div style={{ display: "flex", justifyContent: "space-between", gap: 12 }}>
                <div>
                  <div style={{ fontWeight: 600, marginBottom: 4 }}>
                    {t?.title ?? "Без названия"}
                    {r.status === "interested" && <span style={{ marginLeft: 8 }}>⭐</span>}
                  </div>
                  <div style={{ color: "#555", fontSize: 14, lineHeight: 1.6 }}>
                    Заказчик: {t?.customer ?? "—"}<br />
                    НМЦК: {fmtPrice(t?.price ?? null)} · ОКПД2: {t?.okpd ?? "—"} · регион: {t?.region ?? "—"}<br />
                    Радар: {r.radars?.name ?? "—"}
                  </div>
                </div>
                <div style={{ textAlign: "right", minWidth: 120 }}>
                  {dl != null && (
                    <div style={{ color: urgent ? "crimson" : "#333", fontWeight: urgent ? 700 : 400 }}>
                      {dl < 0 ? "дедлайн прошёл" : dl === 0 ? "сегодня!" : `через ${dl} дн.`}
                    </div>
                  )}
                  {t?.submission_deadline && (
                    <div style={{ color: "#888", fontSize: 13 }}>
                      {new Date(t.submission_deadline).toLocaleDateString("ru-RU")}
                    </div>
                  )}
                </div>
              </div>
              <div style={{ display: "flex", gap: 8, marginTop: 10, alignItems: "center" }}>
                {t?.eis_url && (
                  <a href={t.eis_url} target="_blank" rel="noreferrer"><button>Открыть в ЕИС</button></a>
                )}
                <button onClick={() => setStatus(r.id, "interested")} disabled={r.status === "interested"}>
                  ⭐ Интересно
                </button>
                <button onClick={() => setStatus(r.id, "hidden")} style={{ color: "crimson" }}>
                  Скрыть
                </button>
              </div>
            </div>
          );
        })
      )}
    </main>
  );
}
