"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import RadarForm from "@/components/RadarForm";
import type { RadarRow } from "@/types/db";

export default function EditRadarPage() {
  const params = useParams<{ id: string }>();
  const [radar, setRadar] = useState<RadarRow | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function load() {
      const supabase = createClient();
      const { data } = await supabase.from("radars").select("*").eq("id", params.id).single();
      setRadar((data as RadarRow) ?? null);
      setLoading(false);
    }
    void load();
  }, [params.id]);

  return (
    <main style={{ maxWidth: 600, margin: "2rem auto", padding: "0 1rem", fontFamily: "system-ui, sans-serif" }}>
      <h1>Радар</h1>
      {loading ? <p>Загрузка…</p> : radar ? <RadarForm initial={radar} /> : <p>Радар не найден.</p>}
    </main>
  );
}
